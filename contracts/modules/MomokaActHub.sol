
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {ILensHub} from 'contracts/interfaces/ILensHub.sol';
import {IPublicationActionModule} from 'contracts/interfaces/IPublicationActionModule.sol';

import {HubRestricted} from 'contracts/base/HubRestricted.sol';

import {MetaTxLib} from 'contracts/libraries/MetaTxLib.sol';

import {Types} from 'contracts/libraries/constants/Types.sol';
import {Errors} from 'contracts/libraries/constants/Errors.sol';
import {Events} from 'contracts/libraries/constants/Events.sol';

interface IOracleVerifier {
    function verify(bytes calldata data) external returns (bytes memory);
    function verifyAndStoreActResponse(bytes calldata data) external returns (Types.ActOracleResponse memory);
}

contract MomokaActHub is HubRestricted {

    address oracleImpl;
    mapping (uint256 profileId => mapping (uint256 pubId => uint256)) initializedBitmapByProfileIdPubId;

    modifier onlyProfileOwnerOrDelegatedExecutor(address expectedOwnerOrDelegatedExecutor, uint256 profileId) {
        // Expand from: ValidationLib.validateAddressIsProfileOwnerOrDelegatedExecutor(expectedOwnerOrDelegatedExecutor, profileId);
        ILensHub hub = ILensHub(HUB);
        if (expectedOwnerOrDelegatedExecutor != hub.ownerOf(profileId)) {
            // TODO: Shortcuted because it's not implemente in Lens v1
            revert Errors.ExecutorInvalid();
            // // Expand from: validateAddressIsDelegatedExecutor()
            // // Expand from: isExecutorApproved()
            // if (!hub.isDelegatedExecutorApproved(profileId, expectedOwnerOrDelegatedExecutor)) {
            //     revert Errors.ExecutorInvalid();
            // }
        }
        _;
    }

    modifier whenNotPaused() {
        // Expand from: LensProfiles.whenNotPaused()
        if (ILensHub(HUB).getState() == Types.ProtocolState.Paused) {
            revert Errors.Paused();
        }
        _;
    }

    constructor(address hub, address _oracleImpl) HubRestricted(hub) {
        oracleImpl = _oracleImpl;
    }

    function getOracleImpl() external returns (address) {
        return oracleImpl;
    }


    function momokaAct(
        Types.PublicationActionParams calldata publicationActionParams,
        bytes calldata oracleAttestation
    )
        external
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, publicationActionParams.actorProfileId)
        returns (bytes memory)
    {
        ILensHub hub = ILensHub(HUB);
        return
            _actInternal({
                publicationActionParams: publicationActionParams,
                oracleAttestation: oracleAttestation,
                transactionExecutor: msg.sender,
                actorProfileOwner: hub.ownerOf(publicationActionParams.actorProfileId)
            });
    }

    function momokaActWithSig(
        Types.PublicationActionParams calldata publicationActionParams,
        bytes calldata oracleAttestation,
        Types.EIP712Signature calldata signature
    )
        external
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, publicationActionParams.actorProfileId)
        returns (bytes memory)
    {
        address owner;
        {
            owner = ILensHub(HUB).ownerOf(publicationActionParams.actorProfileId);
        }
        // TODO: be aware of the domain separator
        MetaTxLib.validateActSignature(signature, publicationActionParams);
        return
            _actInternal({
                publicationActionParams: publicationActionParams,
                oracleAttestation: oracleAttestation,
                transactionExecutor: signature.signer,
                actorProfileOwner: owner
            });
    }
    function _actInternal(
        Types.PublicationActionParams calldata publicationActionParams,
        bytes calldata oracleAttestation,
        address transactionExecutor,
        address actorProfileOwner
    ) internal returns (bytes memory) {
        _validateNotBlocked({
            profile: publicationActionParams.actorProfileId,
            byProfile: publicationActionParams.publicationActedProfileId
        });

        Types.ActOracleResponse memory oracleResp = IOracleVerifier(oracleImpl).verifyAndStoreActResponse(oracleAttestation);

        // The oracle request is correct.
        require(oracleResp.profileId == publicationActionParams.publicationActedProfileId, "AT: bad profile id");
        require(oracleResp.pubId == publicationActionParams.publicationActedId, "AT: bad pub id");
        for (uint i = 0; i < publicationActionParams.referrerProfileIds.length; ++i) {
            require(oracleResp.referrerProfileIds[i] == publicationActionParams.referrerProfileIds[i], "AT: bad ref profile id");
            require(oracleResp.referrerPubIds[i] == publicationActionParams.referrerPubIds[i], "AT: bad ref pub id");
        }

        address actionModuleAddress = publicationActionParams.actionModuleAddress;
        // TODO: now we don't check action module whitelist
        //
        // uint256 actionModuleId = StorageLib.actionModuleWhitelistData()[actionModuleAddress].id;
        //
        // if (!_isActionEnabledInMemory(oracleResp.publication, actionModuleId)) {
        //     // This will also revert for:
        //     //   - Non-existent action modules
        //     //   - Non-existent publications
        //     //   - Legacy V1 publications
        //     // Because the storage will be empty.
        //     revert Errors.ActionNotAllowed();
        // }

        _maybInitializeActionModule(
            oracleResp,
            actionModuleAddress,
            transactionExecutor
        );

        Types.PublicationType[] memory referrerPubTypes = oracleResp.referrerPubTypes;
        bytes memory actionModuleReturnData = IPublicationActionModule(actionModuleAddress).processPublicationAction(
            Types.ProcessActionParams({
                publicationActedProfileId: publicationActionParams.publicationActedProfileId,
                publicationActedId: publicationActionParams.publicationActedId,
                actorProfileId: publicationActionParams.actorProfileId,
                actorProfileOwner: actorProfileOwner,
                transactionExecutor: transactionExecutor,
                referrerProfileIds: publicationActionParams.referrerProfileIds,
                referrerPubIds: publicationActionParams.referrerPubIds,
                referrerPubTypes: referrerPubTypes,
                actionModuleData: publicationActionParams.actionModuleData
            })
        );
        emit Events.Acted(publicationActionParams, actionModuleReturnData, block.timestamp);

        return actionModuleReturnData;
    }

    function _validateNotBlocked(uint256 profile, uint256 byProfile) internal view {
        // TODO: Shortcut because it's not implemented in Lens v1
        return;
        // // Expand from: StorageLib.blockedStatus
        // ILensHub hub = ILensHub(HUB);
        // if (hub.isBlocked(profile, byProfile)) {
        //     revert Errors.Blocked();
        // }
    }

    function _maybInitializeActionModule(
        Types.ActOracleResponse memory oracleResponse,
        address moduleAddress,
        address transactionExecutor
    ) internal {
        // Find the index of the action module
        bool found = false;
        uint256 i = 0;
        while (i < oracleResponse.actionModules.length) {
            if (oracleResponse.actionModules[i] == moduleAddress) {
                found = true;
                break;
            }
            unchecked { ++i; }
        }
        require(found, "Action module not defined in the publication");
        // Check if it's initialized
        uint256 bitmap = initializedBitmapByProfileIdPubId[oracleResponse.profileId][oracleResponse.pubId];
        uint256 initBit = 1 << i;
        if ((bitmap & initBit) != 0) {
            // Already initialized
            return;
        }
        // TODO: check return value?
        IPublicationActionModule(moduleAddress).initializePublicationAction(
            oracleResponse.profileId,
            oracleResponse.pubId,
            transactionExecutor,
            oracleResponse.actionModulesInitDatas[i]
        );
        initializedBitmapByProfileIdPubId[oracleResponse.profileId][oracleResponse.pubId]
            = (bitmap | initBit);
    }

    // function _isActionEnabledInMemory(Types.Publication memory _publication, uint256 actionModuleId)
    //     private
    //     pure
    //     returns (bool)
    // {
    //     if (actionModuleId == 0) {
    //         return false;
    //     }
    //     uint256 actionModuleIdBitmapMask = 1 << (actionModuleId - 1);
    //     return actionModuleIdBitmapMask & _publication.enabledActionModulesBitmap != 0;
    // }
}
// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {FollowNFTProxy} from '../upgradeability/FollowNFTProxy.sol';
import {Helpers} from './Helpers.sol';
import {DataTypes} from './DataTypes.sol';
import {Errors} from './Errors.sol';
import {Events} from './Events.sol';
import {Constants} from './Constants.sol';
import {IFollowNFT} from '../interfaces/IFollowNFT.sol';
import {ICollectNFT} from '../interfaces/ICollectNFT.sol';
import {IFollowModule} from '../interfaces/IFollowModule.sol';
import {ICollectModule} from '../interfaces/ICollectModule.sol';
import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

import "hardhat/console.sol";

interface IOracleVerifier {
    function verify(bytes calldata data) external returns (bytes memory);
}

/**
 * @title InteractionLogic
 * @author Lens Protocol
 *
 * @notice This is the library that contains the logic for follows & collects. 
 
 * @dev The functions are external, so they are called from the hub via `delegateCall` under the hood.
 */
library InteractionLogic {
    using Strings for uint256;

    /**
     * @notice Follows the given profiles, executing the necessary logic and module calls before minting the follow
     * NFT(s) to the follower.
     *
     * @param follower The address executing the follow.
     * @param profileIds The array of profile token IDs to follow.
     * @param followModuleDatas The array of follow module data parameters to pass to each profile's follow module.
     * @param _profileById A pointer to the storage mapping of profile structs by profile ID.
     * @param _profileIdByHandleHash A pointer to the storage mapping of profile IDs by handle hash.
     *
     * @return uint256[] An array of integers representing the minted follow NFTs token IDs.
     */
    function follow(
        address follower,
        uint256[] calldata profileIds,
        bytes[] calldata followModuleDatas,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById,
        mapping(bytes32 => uint256) storage _profileIdByHandleHash
    ) external returns (uint256[] memory) {
        if (profileIds.length != followModuleDatas.length) revert Errors.ArrayMismatch();
        uint256[] memory tokenIds = new uint256[](profileIds.length);
        for (uint256 i = 0; i < profileIds.length; ) {
            string memory handle = _profileById[profileIds[i]].handle;
            if (_profileIdByHandleHash[keccak256(bytes(handle))] != profileIds[i])
                revert Errors.TokenDoesNotExist();

            address followModule = _profileById[profileIds[i]].followModule;
            address followNFT = _profileById[profileIds[i]].followNFT;

            if (followNFT == address(0)) {
                followNFT = _deployFollowNFT(profileIds[i]);
                _profileById[profileIds[i]].followNFT = followNFT;
            }

            tokenIds[i] = IFollowNFT(followNFT).mint(follower);

            if (followModule != address(0)) {
                IFollowModule(followModule).processFollow(
                    follower,
                    profileIds[i],
                    followModuleDatas[i]
                );
            }
            unchecked {
                ++i;
            }
        }
        emit Events.Followed(follower, profileIds, followModuleDatas, block.timestamp);
        return tokenIds;
    }

    /**
     * @notice Collects the given publication, executing the necessary logic and module call before minting the
     * collect NFT to the collector.
     *
     * @param collector The address executing the collect.
     * @param profileId The token ID of the publication being collected's parent profile.
     * @param pubId The publication ID of the publication being collected.
     * @param collectModuleData The data to pass to the publication's collect module.
     * @param collectNFTImpl The address of the collect NFT implementation, which has to be passed because it's an immutable in the hub.
     * @param _pubByIdByProfile A pointer to the storage mapping of publications by pubId by profile ID.
     * @param _profileById A pointer to the storage mapping of profile structs by profile ID.
     *
     * @return uint256 An integer representing the minted token ID.
     */
    function collect(
        address collector,
        uint256 profileId,
        uint256 pubId,
        bytes calldata collectModuleData,
        address collectNFTImpl,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _pubByIdByProfile,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById
    ) external returns (uint256) {
        (uint256 rootProfileId, uint256 rootPubId, address rootCollectModule) = Helpers
            .getPointedIfMirror(profileId, pubId, _pubByIdByProfile);

        uint256 tokenId;
        // Avoids stack too deep
        {
            address collectNFT = _pubByIdByProfile[rootProfileId][rootPubId].collectNFT;
            if (collectNFT == address(0)) {
                collectNFT = _deployCollectNFT(
                    rootProfileId,
                    rootPubId,
                    _profileById[rootProfileId].handle,
                    collectNFTImpl
                );
                _pubByIdByProfile[rootProfileId][rootPubId].collectNFT = collectNFT;
            }
            tokenId = ICollectNFT(collectNFT).mint(collector);
        }

        ICollectModule(rootCollectModule).processCollect(
            profileId,
            collector,
            rootProfileId,
            rootPubId,
            collectModuleData
        );
        _emitCollectedEvent(
            collector,
            profileId,
            pubId,
            rootProfileId,
            rootPubId,
            collectModuleData
        );

        return tokenId;
    }

    // structs to avoid "stake too deep" error
    struct DaCollectArgs {
        address collector;
        uint256 profileId;
        uint256 pubId;
        bytes oracleAttestation;
        address collectNFTImpl;
        address oracleImpl;
    }
    struct DaCollectLocals {
        bytes attestedData;
        bytes moduleOracleData;
        uint256 rootProfileId;
        uint256 rootPubId;
        address rootCollectModule;
        string rootContentURI;
    }

    function daCollect(
        DaCollectArgs calldata args,
        bytes calldata collectModuleData,
        mapping(uint256 => mapping(uint256 => DataTypes.PublicationStruct))
            storage _daPubByIdByProfile,
        mapping(uint256 => DataTypes.ProfileStruct) storage _profileById
    ) external returns (uint256) {
        DaCollectLocals memory vars;
        vars.attestedData = IOracleVerifier(args.oracleImpl).verify(args.oracleAttestation);
        {
            bytes memory lensOracleData;
            (lensOracleData, vars.moduleOracleData) = abi.decode(vars.attestedData, (bytes, bytes));
            bytes4 req;
            uint256 attestedProfileId;
            uint256 attestedPubId;
            (
                req,
                attestedProfileId,
                attestedPubId,
                vars.rootProfileId,
                vars.rootPubId,
                vars.rootCollectModule,
                vars.rootContentURI
            ) = abi.decode(lensOracleData, (bytes4, uint256, uint256, uint256, uint256, address, string));

            require(req == bytes4(0x00000000), "AT: bad req");
            require(attestedProfileId == args.profileId, "AT: bad profile id");
            // console.log("pubId", attestedPubId, args.pubId);
            require(attestedPubId == args.pubId, "AT: bad pub id");
        }

        uint256 tokenId;
        // Avoids stack too deep
        {
            address collectNFT = _daPubByIdByProfile[vars.rootProfileId][vars.rootPubId].collectNFT;
            if (collectNFT == address(0)) {
                collectNFT = _deployCollectNFT(
                    vars.rootProfileId,
                    vars.rootPubId,
                    _profileById[vars.rootProfileId].handle,
                    args.collectNFTImpl
                );
                _daPubByIdByProfile[vars.rootProfileId][vars.rootPubId].collectNFT = collectNFT;
                // Must set the fields because it will be checked by Helper.getPointedIfMirror,
                // which is used by LensHub.getContentURI()
                _daPubByIdByProfile[vars.rootProfileId][vars.rootPubId].collectModule = vars.rootCollectModule;
                _daPubByIdByProfile[vars.rootProfileId][vars.rootPubId].contentURI = vars.rootContentURI;
            }
            tokenId = ICollectNFT(collectNFT).mint(args.collector);
        }
        // TODO: initialize the module if it's not yet, since there's no initialization like
        // on-chain publication
        ICollectModule(vars.rootCollectModule).processCollect(
            args.profileId,
            args.collector,
            vars.rootProfileId,
            vars.rootPubId,
            // vars.moduleOracleData,
            collectModuleData
        );
        _emitCollectedEvent(
            args.collector,
            args.profileId,
            args.pubId,
            vars.rootProfileId,
            vars.rootPubId,
            collectModuleData
        );

        return tokenId;
    }

    /**
     * @notice Deploys the given profile's Follow NFT contract.
     *
     * @param profileId The token ID of the profile which Follow NFT should be deployed.
     *
     * @return address The address of the deployed Follow NFT contract.
     */
    function _deployFollowNFT(uint256 profileId) private returns (address) {
        bytes memory functionData = abi.encodeWithSelector(
            IFollowNFT.initialize.selector,
            profileId
        );
        address followNFT = address(new FollowNFTProxy(functionData));
        emit Events.FollowNFTDeployed(profileId, followNFT, block.timestamp);

        return followNFT;
    }

    /**
     * @notice Deploys the given profile's Collect NFT contract.
     *
     * @param profileId The token ID of the profile which Collect NFT should be deployed.
     * @param pubId The publication ID of the publication being collected, which Collect NFT should be deployed.
     * @param handle The profile's associated handle.
     * @param collectNFTImpl The address of the Collect NFT implementation that should be used for the deployment.
     *
     * @return address The address of the deployed Collect NFT contract.
     */
    function _deployCollectNFT(
        uint256 profileId,
        uint256 pubId,
        string memory handle,
        address collectNFTImpl
    ) private returns (address) {
        address collectNFT = Clones.clone(collectNFTImpl);

        bytes4 firstBytes = bytes4(bytes(handle));

        (uint256 pubIdRef, uint256 daId) = Helpers.decomposePubId(pubId);
        string memory collectNFTName = string(
            abi.encodePacked(handle, Constants.COLLECT_NFT_NAME_INFIX, pubIdRef.toString())
        );
        string memory collectNFTSymbol = string(
            abi.encodePacked(firstBytes, Constants.COLLECT_NFT_SYMBOL_INFIX, pubIdRef.toString())
        );
        if (daId > 0) {
            // Add suffix for DA collect
            string memory daId = daId.toHexString();
            collectNFTName = string(
                abi.encodePacked(
                    collectNFTName,
                    Constants.COLLECT_NFT_DA_INFIX,
                    daId
                )
            );
            collectNFTSymbol = string(
                abi.encodePacked(
                    collectNFTSymbol,
                    Constants.COLLECT_NFT_DA_INFIX,
                    daId
                )
            );
        }
        ICollectNFT(collectNFT).initialize(profileId, pubId, collectNFTName, collectNFTSymbol);
        emit Events.CollectNFTDeployed(profileId, pubId, collectNFT, block.timestamp);

        return collectNFT;
    }

    /**
     * @notice Emits the `Collected` event that signals that a successful collect action has occurred.
     *
     * @dev This is done through this function to prevent stack too deep compilation error.
     *
     * @param collector The address collecting the publication.
     * @param profileId The token ID of the profile that the collect was initiated towards, useful to differentiate mirrors.
     * @param pubId The publication ID that the collect was initiated towards, useful to differentiate mirrors.
     * @param rootProfileId The profile token ID of the profile whose publication is being collected.
     * @param rootPubId The publication ID of the publication being collected.
     * @param data The data passed to the collect module.
     */
    function _emitCollectedEvent(
        address collector,
        uint256 profileId,
        uint256 pubId,
        uint256 rootProfileId,
        uint256 rootPubId,
        bytes calldata data
    ) private {
        emit Events.Collected(
            collector,
            profileId,
            pubId,
            rootProfileId,
            rootPubId,
            data,
            block.timestamp
        );
    }
}

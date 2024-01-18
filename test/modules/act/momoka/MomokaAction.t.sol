// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'test/base/BaseTest.t.sol';
import {IPublicationActionModule} from 'contracts/interfaces/IPublicationActionModule.sol';
import {ICollectModule} from 'contracts/interfaces/ICollectModule.sol';
// import {CollectPublicationAction} from 'contracts/modules/act/collect/CollectPublicationAction.sol';
// import {CollectNFT} from 'contracts/modules/act/collect/CollectNFT.sol';
import {MockCollectModule} from 'test/mocks/MockCollectModule.sol';
import {Events} from 'contracts/libraries/constants/Events.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';

import {MetaTxReceiver, OracleVerifier} from 'contracts/misc/LensOracle.sol';
import {MomokaActHub} from 'contracts/modules/MomokaActHub.sol';
import {MomokaCollectNFT} from 'contracts/modules/act/collect/MomokaCollectNFT.sol';
import {MomokaCollectPublicationAction} from 'contracts/modules/act/collect/MomokaCollectPublicationAction.sol';

contract MomokaCollectPublicationActionTest is BaseTest {
    using stdJson for string;
    using Strings for uint256;

    MomokaCollectPublicationAction collectPublicationAction;
    address collectNFTImpl;
    address mockCollectModule;
    OracleVerifier oracleImpl;
    MomokaActHub actHub;
    uint256 constant ATTESTOR_SK = 1;
    string constant CONTENT_URI = "ar://someUri";

    event CollectModuleWhitelisted(address collectModule, bool whitelist, uint256 timestamp);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public override {
        super.setUp();

        // Deploy & Whitelist MockCollectModule
        mockCollectModule = address(new MockCollectModule());
        vm.prank(moduleGlobals.getGovernance());
        collectPublicationAction.whitelistCollectModule(mockCollectModule, true);
    }

    // Deploy CollectPublicationAction
    constructor() TestSetup() {
        if (fork && keyExists(string(abi.encodePacked('.', forkEnv, '.MomokaCollectNFTImpl')))) {
            collectNFTImpl = json.readAddress(string(abi.encodePacked('.', forkEnv, '.MomokaCollectNFTImpl')));
            console.log('Found MomokaCollectNFTImpl deployed at:', address(collectNFTImpl));
        }

        if (fork && keyExists(string(abi.encodePacked('.', forkEnv, '.MomokaCollectPublicationAction')))) {
            collectPublicationAction = MomokaCollectPublicationAction(
                json.readAddress(string(abi.encodePacked('.', forkEnv, '.MomokaCollectPublicationAction')))
            );
            console.log('Found MomokaCollectPublicationAction deployed at:', address(collectPublicationAction));
        }

        // Both deployed - need to verify if they are linked
        if (collectNFTImpl != address(0) && address(collectPublicationAction) != address(0)) {
            if (MomokaCollectNFT(collectNFTImpl).ACTION_MODULE() == address(collectPublicationAction)) {
                console.log('MomokaCollectNFTImpl and MomokaCollectPublicationAction already deployed and linked');
                return;
            }
        }

        uint256 deployerNonce = vm.getNonce(deployer);

        address predictedOracleImpl = computeCreateAddress(deployer, deployerNonce);
        address predictedActHub = computeCreateAddress(deployer, deployerNonce + 1);
        address predictedCollectPublicationAction = computeCreateAddress(deployer, deployerNonce + 2);
        address predictedCollectNFTImpl = computeCreateAddress(deployer, deployerNonce + 3);

        vm.startPrank(deployer);
        // Lens Oracle Verifier, very important
        oracleImpl = new OracleVerifier(vm.addr(ATTESTOR_SK));
        actHub = new MomokaActHub(address(hub), address(oracleImpl));
        collectPublicationAction = new MomokaCollectPublicationAction(
            address(actHub),  // action hub!
            predictedCollectNFTImpl,
            address(moduleGlobals)
        );
        collectNFTImpl = address(new MomokaCollectNFT(address(hub), address(collectPublicationAction), address(oracleImpl)));
        vm.stopPrank();

        assertEq(address(oracleImpl), predictedOracleImpl, 'OracleImpl deployed address mismatch');
        assertEq(address(actHub), predictedActHub, 'ActHub deployed address mismatch');
        assertEq(
            address(collectPublicationAction),
            predictedCollectPublicationAction,
            'MomokaCollectPublicationAction deployed address mismatch'
        );
        assertEq(collectNFTImpl, predictedCollectNFTImpl, 'MomokaCollectNFTImpl deployed address mismatch');

        vm.label(address(collectPublicationAction), 'MomokaCollectPublicationAction');
        vm.label(collectNFTImpl, 'MomokaCollectNFTImpl');
        vm.label(address(oracleImpl), "OracleImpl");
        vm.label(address(actHub), "ActHub");
    }

    // Negatives

    function testCannotInitializePublicationAction_ifNotHub(
        uint256 profileId,
        uint256 pubId,
        address transactionExecutor,
        address from
    ) public {
        vm.assume(profileId != 0);
        vm.assume(pubId != 0);
        vm.assume(transactionExecutor != address(0));
        vm.assume(from != address(hub));

        vm.prank(from);
        vm.expectRevert(Errors.NotHub.selector);
        collectPublicationAction.initializePublicationAction(
            profileId,
            pubId,
            transactionExecutor,
            abi.encode(mockCollectModule, abi.encode(true))
        );
    }

    function testCannotInitializePublicationAction_ifCollectModuleNotWhitelisted(
        uint256 profileId,
        uint256 pubId,
        address transactionExecutor,
        address nonWhitelistedCollectModule
    ) public {
        vm.assume(profileId != 0);
        vm.assume(pubId != 0);
        vm.assume(transactionExecutor != address(0));
        vm.assume(!collectPublicationAction.isCollectModuleWhitelisted(nonWhitelistedCollectModule));

        vm.prank(address(actHub));
        vm.expectRevert(Errors.NotWhitelisted.selector);
        collectPublicationAction.initializePublicationAction(
            profileId,
            pubId,
            transactionExecutor,
            abi.encode(nonWhitelistedCollectModule, '')
        );
    }

    function testCannotProcessPublicationAction_ifNotHub(
        uint256 publicationActedProfileId,
        uint256 publicationActedId,
        uint256 actorProfileId,
        address actorProfileOwner,
        address transactionExecutor,
        address from
    ) public {
        vm.assume(publicationActedProfileId != 0);
        vm.assume(publicationActedId != 0);
        vm.assume(actorProfileId != 0);
        vm.assume(actorProfileOwner != address(0));
        vm.assume(transactionExecutor != address(0));
        vm.assume(from != address(hub));

        vm.prank(from);
        vm.expectRevert(Errors.NotHub.selector);
        collectPublicationAction.processPublicationAction(
            Types.ProcessActionParams({
                publicationActedProfileId: publicationActedProfileId,
                publicationActedId: publicationActedId,
                actorProfileId: actorProfileId,
                actorProfileOwner: actorProfileOwner,
                transactionExecutor: transactionExecutor,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                actionModuleData: ''
            })
        );
    }

    function testCannotProcessPublicationAction_ifCollectActionNotInitialized(
        uint256 publicationActedProfileId,
        uint256 publicationActedId,
        uint256 actorProfileId,
        address actorProfileOwner,
        address transactionExecutor
    ) public {
        vm.assume(publicationActedProfileId != 0);
        vm.assume(publicationActedId != 0);
        vm.assume(actorProfileId != 0);
        vm.assume(actorProfileOwner != address(0));
        vm.assume(transactionExecutor != address(0));

        vm.assume(
            collectPublicationAction.getCollectData(publicationActedProfileId, publicationActedId).collectModule ==
                address(0)
        );

        vm.prank(address(actHub));
        vm.expectRevert(Errors.CollectNotAllowed.selector);
        collectPublicationAction.processPublicationAction(
            Types.ProcessActionParams({
                publicationActedProfileId: publicationActedProfileId,
                publicationActedId: publicationActedId,
                actorProfileId: actorProfileId,
                actorProfileOwner: actorProfileOwner,
                transactionExecutor: transactionExecutor,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                actionModuleData: ''
            })
        );
    }

    // Scenarios
    function testWhitelistCollectModule(address collectModule) public {
        vm.assume(collectModule != address(0));
        vm.assume(!collectPublicationAction.isCollectModuleWhitelisted(collectModule));

        vm.expectEmit(true, true, true, true, address(collectPublicationAction));
        emit CollectModuleWhitelisted(collectModule, true, block.timestamp);
        vm.prank(moduleGlobals.getGovernance());
        collectPublicationAction.whitelistCollectModule(collectModule, true);

        assertTrue(
            collectPublicationAction.isCollectModuleWhitelisted(collectModule),
            'Collect module was not whitelisted'
        );

        vm.expectEmit(true, true, true, true, address(collectPublicationAction));
        emit CollectModuleWhitelisted(collectModule, false, block.timestamp);
        vm.prank(moduleGlobals.getGovernance());
        collectPublicationAction.whitelistCollectModule(collectModule, false);

        assertFalse(
            collectPublicationAction.isCollectModuleWhitelisted(collectModule),
            'Collect module was not removed from whitelist'
        );
    }

    function testInitializePublicationAction(
        uint256 profileId,
        uint256 pubId,
        address transactionExecutor
    ) public {
        vm.assume(profileId != 0);
        vm.assume(pubId != 0);
        vm.assume(transactionExecutor != address(0));

        bytes memory initData = abi.encode(mockCollectModule, abi.encode(true));

        vm.expectCall(
            mockCollectModule,
            abi.encodeCall(
                ICollectModule.initializePublicationCollectModule,
                (profileId, pubId, transactionExecutor, abi.encode(true))
            ),
            1
        );

        vm.prank(address(actHub));
        bytes memory returnData = collectPublicationAction.initializePublicationAction(
            profileId,
            pubId,
            transactionExecutor,
            initData
        );

        assertEq(returnData, initData, 'Return data mismatch');
        assertEq(collectPublicationAction.getCollectData(profileId, pubId).collectModule, mockCollectModule);
    }

    uint256 constant PUB_ID_MASK = (1 << 128) - 1;
    function testProcessPublicationAction_firstCollect(
        uint256 profileId,
        uint256 pubIdRef,
        uint32 daId,
        uint256 actorProfileId,
        address actorProfileOwner,
        address transactionExecutor
    ) public {
        vm.assume(profileId != 0);
        vm.assume(pubIdRef != 0);
        vm.assume(daId != 0);
        vm.assume(actorProfileId != 0);
        vm.assume(actorProfileOwner != address(0));
        vm.assume(transactionExecutor != address(0));
        pubIdRef = pubIdRef & PUB_ID_MASK;
        uint256 pubId = pubIdRef | (uint256(daId) << 128);
        vm.assume(collectPublicationAction.getCollectData(profileId, pubId).collectModule == address(0));

        bytes memory initData = abi.encode(mockCollectModule, abi.encode(true));
        vm.prank(address(actHub));
        collectPublicationAction.initializePublicationAction(profileId, pubId, transactionExecutor, initData);

        Types.ProcessActionParams memory processActionParams = Types.ProcessActionParams({
            publicationActedProfileId: profileId,
            publicationActedId: pubId,
            actorProfileId: actorProfileId,
            actorProfileOwner: actorProfileOwner,
            transactionExecutor: transactionExecutor,
            referrerProfileIds: _emptyUint256Array(),
            referrerPubIds: _emptyUint256Array(),
            referrerPubTypes: _emptyPubTypesArray(),
            actionModuleData: abi.encode(true)
        });

        uint256 contractNonce = vm.getNonce(address(collectPublicationAction));
        address collectNFT = computeCreateAddress(address(collectPublicationAction), contractNonce);

        vm.expectEmit(true, true, true, true, address(collectPublicationAction));
        emit Events.CollectNFTDeployed(profileId, pubId, collectNFT, block.timestamp);

        vm.expectEmit(true, true, true, true, address(collectNFT));
        emit Transfer({from: address(0), to: actorProfileOwner, tokenId: 1});

        vm.expectEmit(true, true, true, true, address(collectPublicationAction));
        emit Events.Collected({
            collectActionParams: processActionParams,
            collectModule: mockCollectModule,
            collectNFT: collectNFT,
            tokenId: 1,
            collectActionResult: abi.encode(true),
            timestamp: block.timestamp
        });

        vm.expectCall(collectNFT, abi.encodeCall(MomokaCollectNFT.initialize, (profileId, pubId)), 1);

        vm.prank(address(actHub));
        bytes memory returnData = collectPublicationAction.processPublicationAction(processActionParams);
        (uint256 tokenId, bytes memory collectActionResult) = abi.decode(returnData, (uint256, bytes));
        assertEq(tokenId, 1, 'Invalid tokenId');
        assertEq(collectActionResult, abi.encode(true), 'Invalid collectActionResult data');

        string memory expectedCollectNftName = string.concat(
            'Lens Collect | Profile #',
            profileId.toString(),
            ' - Publication #',
            pubIdRef.toString(),
            '-DA-',
            toHexString(daId, 4)
        );

        string memory expectedCollectNftSymbol = 'LENS-COLLECT';

        assertEq(MomokaCollectNFT(collectNFT).name(), expectedCollectNftName, 'Invalid collect NFT name');
        assertEq(MomokaCollectNFT(collectNFT).symbol(), expectedCollectNftSymbol, 'Invalid collect NFT symbol');
        assertEq(MomokaCollectNFT(collectNFT).ownerOf(1), actorProfileOwner, 'Invalid collect NFT owner');
    }

    function testCollectPostFromActHub(
        uint256 profileId,
        uint256 pubIdRef,
        uint32 daId
    ) public {
        vm.assume(profileId != 0);
        vm.assume(pubIdRef != 0);
        vm.assume(daId != 0);
        uint256 actorProfileId = defaultAccount.profileId;
        address actorProfileOwner = defaultAccount.owner;
        pubIdRef = pubIdRef & PUB_ID_MASK;
        uint256 pubId = pubIdRef | (uint256(daId) << 128);
        vm.assume(collectPublicationAction.getCollectData(profileId, pubId).collectModule == address(0));

        // TODO: prepare attested data
        bytes memory oracleAttestation = _prepareOracleAttestation(profileId, pubId, address(oracleImpl));
        Types.PublicationActionParams memory publicationActionParams = Types.PublicationActionParams({
            publicationActedProfileId: profileId,
            publicationActedId: pubId,
            actorProfileId: actorProfileId,
            referrerProfileIds: _emptyUint256Array(),
            referrerPubIds: _emptyUint256Array(),
            actionModuleAddress: address(collectPublicationAction),
            actionModuleData: abi.encode(true)
        });
        Types.ProcessActionParams memory processActionParams = Types.ProcessActionParams({
            publicationActedProfileId: profileId,
            publicationActedId: pubId,
            actorProfileId: actorProfileId,
            actorProfileOwner: actorProfileOwner,
            transactionExecutor: actorProfileOwner,
            referrerProfileIds: _emptyUint256Array(),
            referrerPubIds: _emptyUint256Array(),
            referrerPubTypes: _emptyPubTypesArray(),
            actionModuleData: abi.encode(true)
        });

        uint256 contractNonce = vm.getNonce(address(collectPublicationAction));
        address collectNFT = computeCreateAddress(address(collectPublicationAction), contractNonce);

        vm.expectEmit(true, true, true, true, address(collectPublicationAction));
        emit Events.CollectNFTDeployed(profileId, pubId, collectNFT, block.timestamp);

        vm.expectEmit(true, true, true, true, address(collectNFT));
        emit Transfer({from: address(0), to: actorProfileOwner, tokenId: 1});

        vm.expectEmit(true, true, true, true, address(collectPublicationAction));
        emit Events.Collected({
            collectActionParams: processActionParams,
            collectModule: mockCollectModule,
            collectNFT: collectNFT,
            tokenId: 1,
            collectActionResult: abi.encode(true),
            timestamp: block.timestamp
        });

        vm.expectCall(collectNFT, abi.encodeCall(MomokaCollectNFT.initialize, (profileId, pubId)), 1);

        vm.prank(address(actorProfileOwner));
        bytes memory returnData = actHub.momokaAct(publicationActionParams, oracleAttestation);
        (uint256 tokenId, bytes memory collectActionResult) = abi.decode(returnData, (uint256, bytes));
        assertEq(tokenId, 1, 'Invalid tokenId');
        assertEq(collectActionResult, abi.encode(true), 'Invalid collectActionResult data');

        string memory expectedCollectNftName = string.concat(
            'Lens Collect | Profile #',
            profileId.toString(),
            ' - Publication #',
            pubIdRef.toString(),
            '-DA-',
            toHexString(daId, 4)
        );

        string memory expectedCollectNftSymbol = 'LENS-COLLECT';

        assertEq(MomokaCollectNFT(collectNFT).name(), expectedCollectNftName, 'Invalid collect NFT name');
        assertEq(MomokaCollectNFT(collectNFT).symbol(), expectedCollectNftSymbol, 'Invalid collect NFT symbol');

        assertEq(MomokaCollectNFT(collectNFT).ownerOf(1), actorProfileOwner, 'Invalid collect NFT owner');
        assertEq(MomokaCollectNFT(collectNFT).tokenURI(1), CONTENT_URI, 'Invalid content URI');
    }

    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    function toHexString(uint256 value, uint256 length) public returns (string memory) {
        bytes memory buffer = new bytes(2 * length);
        for (int256 i = 2 * int256(length) - 1; i >= 0; --i) {
            buffer[uint256(i)] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        if (value > 0) {
            console.log(value);
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    function _prepareOracleAttestation(
        uint256 profileId,
        uint256 pubId,
        address metaTxReceiver
    ) private returns (bytes memory) {
        Types.ActOracleResponse memory resp = Types.ActOracleResponse({
            profileId: profileId,
            pubId: pubId,
            publication: Types.Publication({
                pointedProfileId: 0,
                pointedPubId: 0,
                contentURI: CONTENT_URI,
                referenceModule: address(0),
                __DEPRECATED__collectModule: address(0),
                __DEPRECATED__collectNFT: address(0),
                pubType: Types.PublicationType.Post,
                rootProfileId: profileId,
                rootPubId: pubId,
                enabledActionModulesBitmap: 0
            }),
            referrerPubTypes: _emptyPubTypesArray(),
            actionModules: _singleAddressArray(address(collectPublicationAction)),
            actionModulesInitDatas: _singleBytesArray(abi.encode(mockCollectModule, abi.encode(true))),
            referrerProfileIds: _emptyUint256Array(),
            referrerPubIds: _emptyUint256Array()
        });

        (
            MetaTxReceiver.ForwardRequest memory metaTx,
            bytes32 sigHash
        ) = MetaTxReceiver(metaTxReceiver).metaTxPrepare({
            from: vm.addr(ATTESTOR_SK),
            data: abi.encode(resp)
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ATTESTOR_SK, sigHash);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertTrue(sig.length == 65);
        return abi.encode(metaTx, sig);
    }

    function _singleAddressArray(address addr) private pure returns (address[] memory) {
        address[] memory result = new address[](1);
        result[0] = addr;
        return result;
    }

    function _singleBytesArray(bytes memory data) private pure returns (bytes[] memory) {
        bytes[] memory result = new bytes[](1);
        result[0] = data;
        return result;
    }
}

pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

import 'contracts/LensHub.sol';
import {OracleVerifier} from 'contracts/misc/LensOracle.sol';
import {FreeCollectModule} from 'contracts/modules/act/collect/FreeCollectModule.sol';
import {MomokaActHub} from 'contracts/modules/MomokaActHub.sol';
import {MomokaCollectPublicationAction} from 'contracts/modules/act/collect/MomokaCollectPublicationAction.sol';
import {MomokaCollectNFT} from 'contracts/modules/act/collect/MomokaCollectNFT.sol';

// import {LensHandles} from 'contracts/misc/namespaces/LensHandles.sol';
// import {TokenHandleRegistry} from 'contracts/misc/namespaces/TokenHandleRegistry.sol';

/**
 * This script will deploy the current repository implementations, using the given environment
 * hub proxy address.
 */
contract DeployMomokaActScript is Script {
    function run() public {
        string memory deployerMnemonic = vm.envString('MNEMONIC');
        uint256 deployerKey = vm.deriveKey(deployerMnemonic, 0);
        address deployer = vm.addr(deployerKey);
        uint256 userKey = vm.deriveKey(deployerMnemonic, 3);
        address hubProxyAddr = vm.envAddress('HUB_PROXY_ADDRESS');

        address owner = deployer;

        // LensHub hub = LensHub(hubProxyAddr);
        // address followNFTAddress = hub.getFollowNFTImpl();
        // address collectNFTAddress = hub.getCollectNFTImpl();


        // Start deployments.
        vm.startBroadcast(deployerKey);

        OracleVerifier oracleImpl = new OracleVerifier(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        // Precompute needed addresss.
        uint256 deployerNonce = vm.getNonce(deployer);
        // address oracleImplAddress = computeCreateAddress(deployer, deployerNonce);
        // address freeCollectAddress = computeCreateAddress(deployer, deployerNonce + 1);
        // address actHubAddress = computeCreateAddress(deployer, deployerNonce + 2);
        // address collectActAddress = computeCreateAddress(deployer, deployerNonce + 3);
        address collectNftAddress = computeCreateAddress(deployer, deployerNonce + 3);

        FreeCollectModule freeCollect = new FreeCollectModule();
        MomokaActHub actHub = new MomokaActHub(hubProxyAddr, address(oracleImpl));
        MomokaCollectPublicationAction collectAct = new MomokaCollectPublicationAction(address(actHub), collectNftAddress, address(0));
        MomokaCollectNFT collectNft = new MomokaCollectNFT(hubProxyAddr, address(collectAct), address(oracleImpl));
        collectAct.whitelistCollectModule(address(freeCollect), true);

        console.log("OracleVerifier", address(oracleImpl));
        console.log("FreeCollectModule", address(freeCollect));
        console.log("MomokaActHub", address(actHub));
        console.log("MomokaCollectPublicationModule", address(collectAct));
        console.log("MomokaCollectNFT", address(collectNft));
        console.log("predicted", collectNftAddress);
        vm.stopBroadcast();

        vm.startBroadcast(userKey);
        {
            bytes memory oracleAttestation = hex"000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000004a0000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000003e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000009087000000000000000000000000f905a0df00000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000038000000000000000000000000000000000000000000000000000000000000003a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000009087000000000000000000000000f905a0df000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004c68747470733a2f2f697066732e747265656a65722e636f6d2f697066732f516d65366d6b4a61756d3655416839707635394248636d556371516e79343855766b474c7833364d763268715056000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000f4054e308f7804e34713c114a0c9e48e786a9a4c000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041563ee1c144308bd91947defd4924fcc6bf842b6d5c5312179e4bf9f3741002941b2af3dd86a73d163634c0638597d64a03d6ec2ff2a23a7260b0f5c5e9abaefa1c00000000000000000000000000000000000000000000000000000000000000";
            actHub.momokaAct(
                Types.PublicationActionParams({
                    publicationActedProfileId: 0x9087,
                    publicationActedId: 0x00f905a0df00000000000000000000000000000002,
                    actorProfileId: 0x90b6,
                    referrerProfileIds: new uint256[](0),
                    referrerPubIds: new uint256[](0),
                    actionModuleAddress: address(collectAct),
                    actionModuleData: new bytes(0)
                }),
                oracleAttestation
            );
        }
        vm.stopBroadcast();
    }
}

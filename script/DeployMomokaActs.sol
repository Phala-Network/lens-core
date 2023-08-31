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
    }
}

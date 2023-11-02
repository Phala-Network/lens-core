// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';
import {CollectPublicationAction} from 'contracts/modules/act/collect/CollectPublicationAction.sol';
import {CollectNFT} from 'contracts/modules/act/collect/CollectNFT.sol';
import {ForkManagement} from 'test/helpers/ForkManagement.sol';
import {LensHub} from 'contracts/LensHub.sol';
import {FeeFollowModule} from 'contracts/modules/follow/FeeFollowModule.sol';
import {RevertFollowModule} from 'contracts/modules/follow/RevertFollowModule.sol';
import {DegreesOfSeparationReferenceModule} from 'contracts/modules/reference/DegreesOfSeparationReferenceModule.sol';
import {FollowerOnlyReferenceModule} from 'contracts/modules/reference/FollowerOnlyReferenceModule.sol';
import {TokenGatedReferenceModule} from 'contracts/modules/reference/TokenGatedReferenceModule.sol';
import {Governance} from 'contracts/misc/access/Governance.sol';
import {ProxyAdmin} from 'contracts/misc/access/ProxyAdmin.sol';
import {ModuleRegistry} from 'contracts/misc/ModuleRegistry.sol';

import {OracleVerifier} from 'contracts/misc/LensOracle.sol';
import {MomokaActHub} from 'contracts/modules/MomokaActHub.sol';
import {MomokaCollectNFT} from 'contracts/modules/act/collect/MomokaCollectNFT.sol';
import {MomokaCollectPublicationAction} from 'contracts/modules/act/collect/MomokaCollectPublicationAction.sol';


contract ContractAddressesLoaderDeployer is Test, ForkManagement {
    using stdJson for string;

    // add this to be excluded from coverage report
    function testContractAddressesLoaderDeployer() public {}

    function loadOrDeploy_GovernanceContract() internal {
        if (fork) {
            if (keyExists(json, string(abi.encodePacked('.', forkEnv, '.GovernanceContract')))) {
                governanceContract = Governance(
                    json.readAddress(string(abi.encodePacked('.', forkEnv, '.GovernanceContract')))
                );
            } else {
                console.log('GovernanceContract key does not exist');
                if (forkVersion == 1) {
                    console.log('No GovernanceContract address found - deploying new one');
                    governanceContract = new Governance(address(hub), governanceMultisig);
                } else {
                    console.log('No GovernanceContract address found in addressBook, which is required for V2');
                    revert('No GovernanceContract address found in addressBook, which is required for V2');
                }
            }
        } else {
            governanceContract = new Governance(address(hub), governanceMultisig);
        }
    }

    function loadOrDeploy_ProxyAdminContract() internal {
        if (fork) {
            if (keyExists(json, string(abi.encodePacked('.', forkEnv, '.ProxyAdminContract')))) {
                proxyAdminContract = ProxyAdmin(
                    json.readAddress(string(abi.encodePacked('.', forkEnv, '.ProxyAdminContract')))
                );
            } else {
                console.log('ProxyAdminContract key does not exist');
                if (forkVersion == 1) {
                    console.log('No ProxyAdminContract address found - deploying new one');
                    proxyAdminContract = new ProxyAdmin(address(hub), address(hubImpl), proxyAdmin);
                } else {
                    console.log('No ProxyAdminContract address found in addressBook, which is required for V2');
                    revert('No ProxyAdminContract address found in addressBook, which is required for V2');
                }
            }
        } else {
            proxyAdminContract = new ProxyAdmin(address(hub), address(hubImpl), proxyAdmin);
        }
    }

    function loadOrDeploy_ModuleRegistryContract() internal {
        if (fork) {
            if (keyExists(json, string(abi.encodePacked('.', forkEnv, '.ModuleRegistry')))) {
                moduleRegistry = ModuleRegistry(
                    json.readAddress(string(abi.encodePacked('.', forkEnv, '.ModuleRegistry')))
                );
            } else {
                console.log('ModuleRegistry key does not exist');
                if (forkVersion == 1) {
                    console.log('No ModuleRegistry address found - deploying new one');
                    moduleRegistry = new ModuleRegistry();
                } else {
                    console.log('No ModuleRegistry address found in addressBook, which is required for V2');
                    revert('No ModuleRegistry address found in addressBook, which is required for V2');
                }
            }
        } else {
            moduleRegistry = new ModuleRegistry(); // TODO: Maybe make it upgradeable if needed
        }
    }

    function loadOrDeploy_CollectPublicationAction() internal returns (address, address) {
        address collectNFTImpl;
        CollectPublicationAction collectPublicationAction;

        // Deploy CollectPublicationAction
        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.CollectNFTImpl')))) {
            collectNFTImpl = json.readAddress(string(abi.encodePacked('.', forkEnv, '.CollectNFTImpl')));
            console.log('Found CollectNFTImpl deployed at:', address(collectNFTImpl));
        }

        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.CollectPublicationAction')))) {
            collectPublicationAction = CollectPublicationAction(
                json.readAddress(string(abi.encodePacked('.', forkEnv, '.CollectPublicationAction')))
            );
            console.log('Found collectPublicationAction deployed at:', address(collectPublicationAction));
        }

        // Both deployed - need to verify if they are linked
        if (collectNFTImpl != address(0) && address(collectPublicationAction) != address(0)) {
            if (CollectNFT(collectNFTImpl).ACTION_MODULE() == address(collectPublicationAction)) {
                console.log('CollectNFTImpl and CollectPublicationAction already deployed and linked');
                return (collectNFTImpl, address(collectPublicationAction));
            }
        }

        uint256 deployerNonce = vm.getNonce(deployer);

        address predictedCollectPublicationAction = computeCreateAddress(deployer, deployerNonce);
        address predictedCollectNFTImpl = computeCreateAddress(deployer, deployerNonce + 1);

        vm.startPrank(deployer);
        collectPublicationAction = new CollectPublicationAction(address(hub), predictedCollectNFTImpl, address(this));
        collectNFTImpl = address(new CollectNFT(address(hub), address(collectPublicationAction)));
        vm.stopPrank();

        assertEq(
            address(collectPublicationAction),
            predictedCollectPublicationAction,
            'CollectPublicationAction deployed address mismatch'
        );
        assertEq(collectNFTImpl, predictedCollectNFTImpl, 'CollectNFTImpl deployed address mismatch');

        vm.label(address(collectPublicationAction), 'CollectPublicationAction');
        vm.label(collectNFTImpl, 'CollectNFTImpl');

        return (collectNFTImpl, address(collectPublicationAction));
    }

    function loadOrDeploy_MomokaCollectPublicationAction() internal returns (MomokaCollectPublicationAction, MomokaActHub, OracleVerifier) {
        MomokaCollectPublicationAction collectPublicationAction;
        address collectNFTImpl;
        OracleVerifier oracleImpl;
        MomokaActHub actHub;

        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.MomokaCollectNFTImpl')))) {
            collectNFTImpl = json.readAddress(string(abi.encodePacked('.', forkEnv, '.MomokaCollectNFTImpl')));
            console.log('Found MomokaCollectNFTImpl deployed at:', address(collectNFTImpl));
        }

        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.MomokaCollectPublicationAction')))) {
            collectPublicationAction = MomokaCollectPublicationAction(
                json.readAddress(string(abi.encodePacked('.', forkEnv, '.MomokaCollectPublicationAction')))
            );
            console.log('Found MomokaCollectPublicationAction deployed at:', address(collectPublicationAction));
        }

        // Both deployed - need to verify if they are linked
        if (collectNFTImpl != address(0) && address(collectPublicationAction) != address(0)) {
            if (MomokaCollectNFT(collectNFTImpl).ACTION_MODULE() == address(collectPublicationAction)) {
                console.log('MomokaCollectNFTImpl and MomokaCollectPublicationAction already deployed and linked');
                revert('loading not supported');
            }
        }

        uint256 deployerNonce = vm.getNonce(deployer);

        address predictedOracleImpl = computeCreateAddress(deployer, deployerNonce);
        address predictedActHub = computeCreateAddress(deployer, deployerNonce + 1);
        address predictedCollectPublicationAction = computeCreateAddress(deployer, deployerNonce + 2);
        address predictedCollectNFTImpl = computeCreateAddress(deployer, deployerNonce + 3);

        vm.startPrank(deployer);
        // Lens Oracle Verifier, very important
        uint256 ATTESTOR_SK = 1;
        oracleImpl = new OracleVerifier(vm.addr(ATTESTOR_SK));
        actHub = new MomokaActHub(address(hub), address(oracleImpl));
        collectPublicationAction = new MomokaCollectPublicationAction(
            address(actHub),  // action hub!
            predictedCollectNFTImpl,
            address(hub)
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
        return (collectPublicationAction, actHub, oracleImpl);
    }

    // function loadOrDeploy_SeaDropMintPublicationAction() internal returns (address) {}

    function loadOrDeploy_FeeFollowModule() internal returns (address) {
        address feeFollowModule;
        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.FeeFollowModule')))) {
            feeFollowModule = json.readAddress(string(abi.encodePacked('.', forkEnv, '.FeeFollowModule')));
            console.log('Testing against already deployed module at:', feeFollowModule);
        } else {
            vm.prank(deployer);
            feeFollowModule = address(new FeeFollowModule(address(hub), address(moduleRegistry), address(this)));
        }
        return feeFollowModule;
    }

    function loadOrDeploy_RevertFollowModule() internal returns (address) {
        address revertFollowModule;
        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.RevertFollowModule')))) {
            revertFollowModule = json.readAddress(string(abi.encodePacked('.', forkEnv, '.RevertFollowModule')));
            console.log('Testing against already deployed module at:', revertFollowModule);
        } else {
            vm.prank(deployer);
            revertFollowModule = address(new RevertFollowModule(address(this)));
        }
        return revertFollowModule;
    }

    function loadOrDeploy_DegreesOfSeparationReferenceModule() internal returns (address) {
        address degreesOfSeparationReferenceModule;
        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.DegreesOfSeparationReferenceModule')))) {
            degreesOfSeparationReferenceModule = json.readAddress(
                string(abi.encodePacked('.', forkEnv, '.DegreesOfSeparationReferenceModule'))
            );
            console.log('Testing against already deployed module at:', degreesOfSeparationReferenceModule);
        } else {
            vm.prank(deployer);
            degreesOfSeparationReferenceModule = address(
                new DegreesOfSeparationReferenceModule(hubProxyAddr, address(this))
            );
        }
        return degreesOfSeparationReferenceModule;
    }

    function loadOrDeploy_FollowerOnlyReferenceModule() internal returns (address) {
        address followerOnlyReferenceModule;
        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.FollowerOnlyReferenceModule')))) {
            followerOnlyReferenceModule = json.readAddress(
                string(abi.encodePacked('.', forkEnv, '.FollowerOnlyReferenceModule'))
            );
            console.log('Testing against already deployed module at:', followerOnlyReferenceModule);
        } else {
            vm.prank(deployer);
            followerOnlyReferenceModule = address(new FollowerOnlyReferenceModule(hubProxyAddr, address(this)));
        }
        return followerOnlyReferenceModule;
    }

    function loadOrDeploy_TokenGatedReferenceModule() internal returns (address) {
        address tokenGatedReferenceModule;
        if (fork && keyExists(json, string(abi.encodePacked('.', forkEnv, '.TokenGatedReferenceModule')))) {
            tokenGatedReferenceModule = json.readAddress(
                string(abi.encodePacked('.', forkEnv, '.TokenGatedReferenceModule'))
            );
            console.log('Testing against already deployed module at:', tokenGatedReferenceModule);
        } else {
            vm.prank(deployer);
            tokenGatedReferenceModule = address(new TokenGatedReferenceModule(hubProxyAddr, address(this)));
        }
        return tokenGatedReferenceModule;
    }
}

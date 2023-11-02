// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {ICollectModule} from 'contracts/modules/interfaces/ICollectModule.sol';
import {ModuleTypes} from 'contracts/modules/libraries/constants/ModuleTypes.sol';
import {LensModuleMetadata} from 'contracts/modules/LensModuleMetadata.sol';

/**
 * @title FreeCollectModule
 * @author Lens Protocol
 *
 * @notice This is a simple Lens CollectModule implementation, inheriting from the ICollectModule interface.
 *
 * This module works by allowing all collects.
 */
contract FreeCollectModule is LensModuleMetadata, ICollectModule {
    function testMockCollectModule() public {
        // Prevents being counted in Foundry Coverage
    }

    function supportsInterface(bytes4 interfaceID) public pure override returns (bool) {
        return interfaceID == type(ICollectModule).interfaceId;
    }

    constructor(address moduleOwner) LensModuleMetadata(moduleOwner) {}

    /**
     * @dev There is nothing needed at initialization.
     */
    function initializePublicationCollectModule(
        uint256,
        uint256,
        address,
        bytes calldata data
    ) external pure override returns (bytes memory) {
        return data;
    }

    /**
     * @dev Processes a collect by:
     *  1. Ensuring the collector is a follower, if needed
     */
    function processCollect(
        ModuleTypes.ProcessCollectParams calldata processCollectParams
    ) external pure override returns (bytes memory) {
        return processCollectParams.data;
    }
}

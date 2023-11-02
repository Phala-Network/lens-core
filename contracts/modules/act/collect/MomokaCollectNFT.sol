// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import {ERC2981CollectionRoyalties} from 'contracts/base/ERC2981CollectionRoyalties.sol';
import {Errors} from 'contracts/libraries/constants/Errors.sol';
import {ICollectNFT} from 'contracts/interfaces/ICollectNFT.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {Strings} from '@openzeppelin/contracts/utils/Strings.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {ILensHub} from 'contracts/interfaces/ILensHub.sol';
import {LensBaseERC721} from 'contracts/base/LensBaseERC721.sol';
import {ActionRestricted} from 'contracts/modules/ActionRestricted.sol';
// import "forge-std/console.sol";
interface IPublicationProvider {
    function getContentURI(uint256 profileId, uint256 pubId) external view returns (string memory);
}

/**
 * @title MomokaCollectNFT
 * @author Lens Protocol
 *
 * @dev This is the MomokaCollectNFT for Lens V2, it differs from LegacyCollectNFT that it's restricted to be called by an
 * action module instead of LensHub.
 *
 * @notice This is the NFT contract that is minted upon collecting a given publication. It is cloned upon
 * the first collect for a given publication, and the token URI points to the original publication's contentURI.
 */
contract MomokaCollectNFT is LensBaseERC721, ERC2981CollectionRoyalties, ActionRestricted, ICollectNFT {
    using Strings for uint256;

    address public immutable HUB;
    address public immutable PUBLICATION_PROVIDER;

    uint256 internal _profileId;
    uint256 internal _pubId;
    uint256 internal _tokenIdCounter;

    bool private _initialized;

    uint256 internal _royaltiesInBasisPoints;

    // We create the MomokaCollectNFT with the pre-computed HUB address before deploying the hub proxy in order
    // to initialize the hub proxy at construction.
    constructor(address hub, address actionModule, address publicationProvider) ActionRestricted(actionModule) {
        HUB = hub;
        PUBLICATION_PROVIDER = publicationProvider;
        _initialized = true;
    }

    /// @inheritdoc ICollectNFT
    function initialize(uint256 profileId, uint256 pubId) external override {
        if (_initialized) revert Errors.Initialized();
        _initialized = true;
        _setRoyalty(1000); // 10% of royalties
        _profileId = profileId;
        _pubId = pubId;
        // _name and _symbol remain uninitialized because we override the getters below
    }

    /// @inheritdoc ICollectNFT
    function mint(address to) external override onlyActionModule returns (uint256) {
        unchecked {
            uint256 tokenId = ++_tokenIdCounter;
            _mint(to, tokenId);
            return tokenId;
        }
    }

    /// @inheritdoc ICollectNFT
    function getSourcePublicationPointer() external view override returns (uint256, uint256) {
        return (_profileId, _pubId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) revert Errors.TokenDoesNotExist();
        return IPublicationProvider(PUBLICATION_PROVIDER).getContentURI(_profileId, _pubId);

    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view override returns (string memory) {
        (uint256 pubIdRef, uint256 daId) = decomposePubId(_pubId);
        return string.concat(
            'Lens Collect | Profile #',
            _profileId.toString(),
            ' - Publication #',
            pubIdRef.toString(),
            '-DA-',
            toHexString(daId, 4)
        );
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public pure override returns (string memory) {
        return 'LENS-COLLECT';
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC2981CollectionRoyalties, LensBaseERC721)
        returns (bool)
    {
        return
            ERC2981CollectionRoyalties.supportsInterface(interfaceId) || LensBaseERC721.supportsInterface(interfaceId);
    }

    function _getReceiver(
        uint256 /* tokenId */
    ) internal view override returns (address) {
        return IERC721(HUB).ownerOf(_profileId);
    }

    function _beforeRoyaltiesSet(
        uint256 /* royaltiesInBasisPoints */
    ) internal view override {
        if (IERC721(HUB).ownerOf(_profileId) != msg.sender) {
            revert Errors.NotProfileOwner();
        }
    }

    function _getRoyaltiesInBasisPointsSlot() internal pure override returns (uint256) {
        uint256 slot;
        assembly {
            slot := _royaltiesInBasisPoints.slot
        }
        return slot;
    }
    
    // Helper functions

    uint256 constant MASK = (1 << 128) - 1;
    // returns (pubId, daId)
    function decomposePubId(uint256 pubId) internal pure returns (uint256, uint256) {
        return (pubId & MASK, (pubId >> 128) & 0xFFFFFFFF);
    }

    // Modified from OpenZeppelin String library

    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length);
        for (int256 i = 2 * int256(length) - 1; i >= 0; --i) {
            buffer[uint256(i)] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

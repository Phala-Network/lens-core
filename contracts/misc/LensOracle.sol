// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (metatx/MinimalForwarder.sol)
// Modified by Phala Network, 2023

pragma solidity ^0.8.15;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import {Types} from 'contracts/libraries/constants/Types.sol';

contract MetaTxReceiver is EIP712, Context {
    using ECDSA for bytes32;

    struct ForwardRequest {
        address from;
        uint256 nonce;
        bytes data;
    }

    bytes32 private constant _TYPEHASH =
        keccak256("ForwardRequest(address from,uint256 nonce,bytes data)");
    
    error NonceTooLow(uint256 actual, uint256 currentNonce);
    error MetaTxSignatureNotMatch();

    mapping(address => uint256) private _nonces;

    constructor() EIP712("PhatRollupMetaTxReceiver", "0.0.1") {}

    // View functions for signer

    function metaTxGetNonce(address from) public view returns (uint256) {
        // return _nonces[from];
        return 0;
    }

    function metaTxPrepare(address from, bytes calldata data) public view returns (ForwardRequest memory, bytes32) {
        return metaTxPrepareWithNonce(from, data, _nonces[from]);
    }

    function metaTxPrepareWithNonce(address from, bytes calldata data, uint256 nonce) public view returns (ForwardRequest memory, bytes32) {
        if (nonce < _nonces[from]) {
            revert NonceTooLow(nonce, _nonces[from]);
        }
        ForwardRequest memory req = ForwardRequest(from, nonce, data);
        bytes32 hash = _hashTypedDataV4(
            keccak256(abi.encode(_TYPEHASH, from, nonce, keccak256(data)))
        );
        return (req, hash);
    }

    // Verification functions

    function metaTxVerify(ForwardRequest memory req, bytes memory signature) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(_TYPEHASH, req.from, req.nonce, keccak256(req.data)))
        ).recover(signature);
        return /*_nonces[req.from] == req.nonce &&*/ signer == req.from;
    }

    modifier useMetaTx(
        ForwardRequest memory req,
        bytes memory signature
    ) {
        if (!metaTxVerify(req, signature)) {
            revert MetaTxSignatureNotMatch();
        }
        _nonces[req.from] = req.nonce + 1;
        _;
    }
}

interface IOracleVerifier {
    function verify(bytes calldata data) external returns (bytes memory);
    function verifyAndStoreActResponse(bytes calldata data) external returns (Types.ActOracleResponse memory);
}

interface IPublicationProvider {
    function getContentURI(uint256 profileId, uint256 pubId) external view returns (string memory);
}

contract OracleVerifier is MetaTxReceiver, IOracleVerifier {
    // Attested publications
    mapping(uint256 profileId => mapping(uint256 pubId => Types.PublicationMemory publication)) verifiedPublications;

    // The oracle owned address for verifying signed data
    address attester;
    bool bypassCheck;
    constructor(address _attestor) {
        attester = _attestor;
    }
    function resetAttestor(address _attestor) external {
        attester = _attestor;
    }
    function setBypassCheck(bool _bypassCheck) external {
        bypassCheck = _bypassCheck;
    }

    function verify(bytes calldata data) view public returns (bytes memory) {
        (MetaTxReceiver.ForwardRequest memory metaTx, bytes memory sig) = abi.decode(data, (MetaTxReceiver.ForwardRequest, bytes));
        if (!bypassCheck) {
            require(metaTx.from == attester, "Invalid attestation signer");
            metaTxVerify(metaTx, sig);
        }
        return metaTx.data;
    }

    function verifyAndStoreActResponse(bytes calldata data) external returns (Types.ActOracleResponse memory) {
        bytes memory innerData = verify(data);
        Types.ActOracleResponse memory response = abi.decode(innerData, (Types.ActOracleResponse));
        verifiedPublications[response.profileId][response.pubId] = response.publication;
        return response;
    }

    function getContentURI(uint256 profileId, uint256 pubId) external view returns (string memory) {
        Types.PublicationMemory storage _publication = verifiedPublications[profileId][pubId];

        // Just revert in the first two branches, because it's supposed to collect the root post
        // instead of any intermediary referencing posts. So finally, simply return the post
        // contentURI.

        Types.PublicationType pubType = _publication.pubType;
        if (pubType == Types.PublicationType.Nonexistent) {
            revert("Nonexistent post should not exist.");
            // pubType = getPublicationType(profileId, pubId);
        }
        if (pubType == Types.PublicationType.Mirror) {
            revert("Collecting a mirror is not supported.");
            // return StorageLib.getPublication(_publication.pointedProfileId, _publication.pointedPubId).contentURI;
        } else {
            // return StorageLib.getPublication(profileId, pubId).contentURI;
            return _publication.contentURI;
        }
    }
}
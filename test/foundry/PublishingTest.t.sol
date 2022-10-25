// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import './base/BaseTest.t.sol';
import './helpers/SignatureHelpers.sol';
import './helpers/PublishingHelpers.sol';

contract SigSetup {
    uint256 nonce;
    uint256 deadline;

    function setUp() public virtual {
        nonce = 0;
        deadline = type(uint256).max;
    }
}

contract PublishingTest_Post is BaseTest, SignatureHelpers, PublishingHelpers, SigSetup {
    function setUp() public override(SigSetup, TestSetup) {
        TestSetup.setUp();
        SigSetup.setUp();
    }

    // negatives
    function testPostNotExecutorFails() public {
        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _post(mockPostData);
    }

    function testPostWithSigInvalidSignerFails() public {
        bytes32 digest = _getPostTypedDataHash(mockPostData, nonce, deadline);

        vm.expectRevert(Errors.SignatureInvalid.selector);
        _postWithSig(
            _buildPostWithSigData({
                delegatedSigner: address(0),
                postData: mockPostData,
                sig: _getSigStruct(otherSignerKey, digest, deadline)
            })
        );
    }

    function testPostWithSigNotExecutorFails() public {
        bytes32 digest = _getPostTypedDataHash(mockPostData, nonce, deadline);

        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _postWithSig(
            _buildPostWithSigData({
                delegatedSigner: otherSigner,
                postData: mockPostData,
                sig: _getSigStruct(otherSignerKey, digest, deadline)
            })
        );
    }

    // positives
    function testPost() public {
        vm.prank(profileOwner);
        uint256 pubId = _post(mockPostData);
        assertEq(pubId, 1);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockPostData));
    }

    function testExecutorPost() public {
        vm.prank(profileOwner);
        _setDelegatedExecutorApproval(otherSigner, true);

        vm.prank(otherSigner);
        uint256 pubId = _post(mockPostData);
        assertEq(pubId, 1);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockPostData));
    }

    function testExecutorPostWithSig() public {
        vm.prank(profileOwner);
        _setDelegatedExecutorApproval(otherSigner, true);

        uint256 nonce = 0;
        uint256 deadline = type(uint256).max;
        bytes32 digest = _getPostTypedDataHash(mockPostData, nonce, deadline);

        uint256 pubId = _postWithSig(
            _buildPostWithSigData({
                delegatedSigner: otherSigner,
                postData: mockPostData,
                sig: _getSigStruct(otherSignerKey, digest, deadline)
            })
        );
        assertEq(pubId, 1);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockPostData));
    }
}

contract PublishingTest_Comment is BaseTest, SignatureHelpers, PublishingHelpers, SigSetup {
    function setUp() public override(SigSetup, TestSetup) {
        TestSetup.setUp();
        SigSetup.setUp();

        vm.prank(profileOwner);
        _post(mockPostData);
    }

    // Negatives
    function testCommentNotExecutorFails() public {
        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _comment(mockCommentData);
    }

    function testCommentWithSigInvalidSignerFails() public {
        bytes32 digest = _getCommentTypedDataHash(mockCommentData, nonce, deadline);
        DataTypes.EIP712Signature memory sig = _getSigStruct(otherSignerKey, digest, deadline);

        vm.expectRevert(Errors.SignatureInvalid.selector);
        _commentWithSig(
            _buildCommentWithSigData({
                delegatedSigner: address(0),
                commentData: mockCommentData,
                sig: sig
            })
        );
    }

    function testCommentWithSigNotExecutorFails() public {
        bytes32 digest = _getCommentTypedDataHash(mockCommentData, nonce, deadline);
        DataTypes.EIP712Signature memory sig = _getSigStruct(otherSignerKey, digest, deadline);

        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _commentWithSig(
            _buildCommentWithSigData({
                delegatedSigner: otherSigner,
                commentData: mockCommentData,
                sig: sig
            })
        );
    }

    // positives
    function testComment() public {
        vm.prank(profileOwner);
        uint256 pubId = _comment(mockCommentData);
        assertEq(pubId, 2);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockCommentData));
    }

    function testExecutorComment() public {
        vm.prank(profileOwner);
        _setDelegatedExecutorApproval(otherSigner, true);

        vm.prank(otherSigner);
        uint256 pubId = _comment(mockCommentData);
        assertEq(pubId, 2);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockCommentData));
    }

    function testExecutorCommentWithSig() public {
        vm.prank(profileOwner);
        _setDelegatedExecutorApproval(otherSigner, true);

        bytes32 digest = _getCommentTypedDataHash(mockCommentData, nonce, deadline);
        DataTypes.EIP712Signature memory sig = _getSigStruct(otherSignerKey, digest, deadline);

        uint256 pubId = _commentWithSig(
            _buildCommentWithSigData({
                delegatedSigner: otherSigner,
                commentData: mockCommentData,
                sig: sig
            })
        );
        assertEq(pubId, 2);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockCommentData));
    }
}

contract PublishingTest_Mirror is BaseTest, SignatureHelpers, PublishingHelpers, SigSetup {
    function setUp() public override(SigSetup, TestSetup) {
        TestSetup.setUp();
        SigSetup.setUp();
        vm.prank(profileOwner);
        _post(mockPostData);
    }

    // Negatives
    function testMirrorNotExecutorFails() public {
        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _mirror(mockMirrorData);
    }

    function testMirrorWithSigInvalidSignerFails() public {
        bytes32 digest = _getMirrorTypedDataHash(mockMirrorData, nonce, deadline);

        vm.expectRevert(Errors.SignatureInvalid.selector);
        _mirrorWithSig(
            _buildMirrorWithSigData({
                delegatedSigner: address(0),
                mirrorData: mockMirrorData,
                sig: _getSigStruct(otherSignerKey, digest, deadline)
            })
        );
    }

    function testMirrorWithSigNotExecutorFails() public {
        bytes32 digest = _getMirrorTypedDataHash(mockMirrorData, nonce, deadline);

        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _mirrorWithSig(
            _buildMirrorWithSigData({
                delegatedSigner: otherSigner,
                mirrorData: mockMirrorData,
                sig: _getSigStruct(otherSignerKey, digest, deadline)
            })
        );
    }

    // Positives

    function testMirror() public {
        vm.prank(profileOwner);
        uint256 pubId = _mirror(mockMirrorData);
        assertEq(pubId, 2);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockMirrorData));
    }

    function testExecutorMirror() public {
        vm.prank(profileOwner);
        _setDelegatedExecutorApproval(otherSigner, true);

        vm.prank(otherSigner);
        uint256 pubId = _mirror(mockMirrorData);
        assertEq(pubId, 2);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockMirrorData));
    }

    function testExecutorMirrorWithSig() public {
        vm.prank(profileOwner);
        _setDelegatedExecutorApproval(otherSigner, true);

        bytes32 digest = _getMirrorTypedDataHash(mockMirrorData, nonce, deadline);

        uint256 pubId = _mirrorWithSig(
            _buildMirrorWithSigData({
                delegatedSigner: otherSigner,
                mirrorData: mockMirrorData,
                sig: _getSigStruct(otherSignerKey, digest, deadline)
            })
        );
        assertEq(pubId, 2);

        DataTypes.PublicationStruct memory pub = _getPub(firstProfileId, pubId);
        _verifyPublication(pub, _expectedPubFromInitData(mockMirrorData));
    }
}

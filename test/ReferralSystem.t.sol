// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import 'test/mocks/MockModule.sol';
import 'test/base/BaseTest.t.sol';
import {MockDeprecatedCollectModule} from 'test/mocks/MockDeprecatedCollectModule.sol';

/*
This kind of tree is created:

    Post_1
    |
    |-- Comment/Quote_0 -- Mirror_0 (mirror of a direct reference)
    |        |
    |        |-- Comment/Quote_1 -- Mirror_1 (mirror of a 1st level reference)
    |                 |
    |                 |-- Comment/Quote_2 -- Mirror_2 (mirror of a 2nd level reference)
    |                           |
    |                           |-- Comment/Quote_3 -- Mirror_3 (mirror of a 3rd level reference)
    |
    |
    |-- Comment/Quote_4 -- Mirror_4 (a different branch)
    |
    |
    |-- Mirror_5 (direct post mirror)
*/

/**
 * Tests shared among all operations where the Lens V2 Referral System applies, e.g. act, quote, comment, mirror.
 */
abstract contract ReferralSystemTest is BaseTest {
    uint256 testAccountId;

    function _referralSystem_PrepareOperation(
        TestPublication memory target,
        TestPublication memory referralPub
    ) internal virtual;

    function _referralSystem_ExecutePreparedOperation(
        TestPublication memory target,
        TestPublication memory referralPub
    ) internal virtual;

    function _executeOperation(TestPublication memory target, TestPublication memory referralPub) private {
        _referralSystem_PrepareOperation(target, referralPub);
        _referralSystem_ExecutePreparedOperation(target, referralPub);
    }

    function setUp() public virtual override {
        super.setUp();
    }

    struct Tree {
        TestPublication post;
        TestPublication[] references;
        TestPublication[] mirrors;
    }

    function testV2Referrals() public virtual {
        for (uint256 commentQuoteFuzzBitmap = 0; commentQuoteFuzzBitmap < 32; commentQuoteFuzzBitmap++) {
            Tree memory treeV2 = _createV2Tree(commentQuoteFuzzBitmap);
            {
                // Target a post with quote/comment as referrals
                TestPublication memory target = treeV2.post;
                for (uint256 i = 0; i < treeV2.references.length; i++) {
                    TestPublication memory referralPub = treeV2.references[i];
                    _executeOperation(target, referralPub);
                }
            }

            {
                // Target a post with mirrors as referrals
                TestPublication memory target = treeV2.post;
                for (uint256 i = 0; i < treeV2.mirrors.length; i++) {
                    TestPublication memory referralPub = treeV2.mirrors[i];
                    _executeOperation(target, referralPub);
                }
            }

            {
                // Target as a quote/comment node and pass another quote/comments as referral
                for (uint256 i = 0; i < treeV2.references.length; i++) {
                    TestPublication memory target = treeV2.references[i];
                    for (uint256 j = 0; j < treeV2.references.length; j++) {
                        TestPublication memory referralPub = treeV2.references[j];
                        if (i == j) continue; // skip self
                        // vm.expectCall /* */();

                        _executeOperation(target, referralPub);
                    }

                    // One special case is a post as referal for reference node
                    TestPublication memory referralPub = treeV2.post;
                    // vm.expectCall /* */();
                    _executeOperation(target, referralPub);
                }
            }

            {
                // Target as a quote/comment node and pass mirror as referral
                for (uint256 i = 0; i < treeV2.references.length; i++) {
                    TestPublication memory target = treeV2.references[i];
                    for (uint256 j = 0; j < treeV2.mirrors.length; j++) {
                        TestPublication memory referralPub = treeV2.mirrors[j];
                        if (i == j) continue; // skip self
                        // vm.expectCall /* */();

                        _executeOperation(target, referralPub);
                    }
                }
            }
        }
    }

    // function testV1_TargetPost_ReferralComment(uint256 v1FuzzBitmap) public virtual {
    //     vm.assume(v1FuzzBitmap < 2 ** 11);
    //     uint256 commentQuoteFuzzBitmap = 0;
    //     Tree memory treeV1 = _createV1Tree(commentQuoteFuzzBitmap, v1FuzzBitmap);

    //     // Target a post with quote/comment as referrals
    //     TestPublication memory target = treeV1.post;
    //     for (uint256 i = 0; i < treeV1.references.length; i++) {
    //         TestPublication memory referralPub = treeV1.references[i];
    //         // should revert because only mirros are allowed as referrals on V1 pubs
    //         _executeOperationV1(target, referralPub, true);
    //     }
    // }

    // function testV1_TargetPost_ReferralMirror(uint256 v1FuzzBitmap) public virtual {
    //     vm.assume(v1FuzzBitmap < 2 ** 11);
    //     uint256 commentQuoteFuzzBitmap = 0;
    //     Tree memory treeV1 = _createV1Tree(commentQuoteFuzzBitmap, v1FuzzBitmap);

    //     // Target a post with quote/comment as referrals
    //     TestPublication memory target = treeV1.post;
    //     for (uint256 i = 0; i < treeV1.mirrors.length; i++) {
    //         TestPublication memory referralPub = treeV1.mirrors[i];
    //         Types.Publication memory publication = hub.getPublication(referralPub.profileId, referralPub.pubId);
    //         if (publication.pointedProfileId == target.profileId && publication.pointedPubId == target.pubId) {
    //             _executeOperationV1(target, referralPub, false);
    //         } else {
    //             // should revert as only mirrors pointing to the target are allowed as referrals on V1 pubs
    //             _executeOperationV1(target, referralPub, true);
    //         }
    //     }
    // }

    // function testV1_TargetComment_ReferralPost(uint256 v1FuzzBitmap) public virtual {
    //     vm.assume(v1FuzzBitmap < 2 ** 11);
    //     uint256 commentQuoteFuzzBitmap = 0;
    //     Tree memory treeV1 = _createV1Tree(commentQuoteFuzzBitmap, v1FuzzBitmap);

    //     // Target comment with post as a referral
    //     TestPublication memory referralPub = treeV1.post;
    //     for (uint256 i = 0; i < treeV1.references.length; i++) {
    //         TestPublication memory target = treeV1.references[i];

    //         // check if target is V2 or V1
    //         Types.Publication memory targetPublication = hub.getPublication(target.profileId, target.pubId);
    //         if (_isV1LegacyPub(targetPublication)) {
    //             // Shoule revert as V1-contaminated trees don't have a root and only allow downwards referrals
    //             _executeOperationV1(target, referralPub, true);
    //         } else {
    //             // Shoule revert as V1-contaminated trees don't have a root and only allow downwards referrals
    //             _executeOperationV2(target, referralPub, true);
    //         }
    //     }
    // }

    function _createV2Tree(uint256 commentQuoteFuzzBitmap) internal returns (Tree memory) {
        Tree memory tree;
        tree.references = new TestPublication[](5);
        tree.mirrors = new TestPublication[](6);

        tree.post = _post();

        tree.references[0] = _commentOrQuote(tree.post, commentQuoteFuzzBitmap, 0);
        tree.mirrors[0] = _mirror(tree.references[0]);
        tree.references[1] = _commentOrQuote(tree.references[0], commentQuoteFuzzBitmap, 1);
        tree.mirrors[1] = _mirror(tree.references[1]);
        tree.references[2] = _commentOrQuote(tree.references[1], commentQuoteFuzzBitmap, 2);
        tree.mirrors[2] = _mirror(tree.references[2]);
        tree.references[3] = _commentOrQuote(tree.references[2], commentQuoteFuzzBitmap, 3);
        tree.mirrors[3] = _mirror(tree.references[3]);

        tree.references[4] = _commentOrQuote(tree.post, commentQuoteFuzzBitmap, 4);
        tree.mirrors[4] = _mirror(tree.references[4]);

        tree.mirrors[5] = _mirror(tree.post);

        return tree;
    }

    function _isV1LegacyPub(Types.Publication memory pub) internal pure returns (bool) {
        return uint8(pub.pubType) == 0;
    }

    function _convertToV1(TestPublication memory pub, uint256 v1FuzzBitmap, uint256 v1FuzzBitmapIndex) internal {
        Types.Publication memory publication = hub.getPublication(pub.profileId, pub.pubId);
        Types.Publication memory pointedPub = hub.getPublication(
            publication.pointedProfileId,
            publication.pointedPubId
        );
        if (_isV1LegacyPub(pointedPub)) {
            bool shouldConvertToV1 = ((v1FuzzBitmap >> (v1FuzzBitmapIndex)) & 1) != 0;
            if (shouldConvertToV1) {
                console.log('Converted (%s, %s) to V1', pub.profileId, pub.pubId);
                _toLegacyV1Pub(
                    pub.profileId,
                    pub.pubId,
                    publication.referenceModule,
                    publication.pubType == Types.PublicationType.Mirror ? address(0) : address(69)
                );
            }
        }
    }

    function _convertPostToV1(TestPublication memory pub) internal {
        Types.Publication memory publication = hub.getPublication(pub.profileId, pub.pubId);
        console.log('Converted (%s, %s) to V1', pub.profileId, pub.pubId);
        address mockDeprecatedCollectModule = address(new MockDeprecatedCollectModule());
        _toLegacyV1Pub(pub.profileId, pub.pubId, publication.referenceModule, mockDeprecatedCollectModule);
    }

    // function _createV1Tree(uint256 commentQuoteFuzzBitmap, uint256 v1FuzzBitmap) internal returns (Tree memory) {
    //     /*
    //         Post_1 [Always V1]
    //         |
    //         |-- Comment/Quote_0 -- Mirror_0 (mirror of a direct reference)
    //         |        |
    //         |        |-- Comment/Quote_1 -- Mirror_1 (mirror of a 1st level reference)
    //         |                 |
    //         |                 |-- Comment/Quote_2 -- Mirror_2 (mirror of a 2nd level reference)
    //         |                           |
    //         |                           |-- Comment/Quote_3 -- Mirror_3 (mirror of a 3rd level reference)

    //         |
    //         |-- Comment/Quote_4 -- Mirror_4 (a different branch)
    //         |
    //         |
    //         |-- Mirror_5 (direct post mirror)
    //     */

    //     Tree memory tree;
    //     tree.references = new TestPublication[](5);
    //     tree.mirrors = new TestPublication[](6);

    //     tree.post = post();
    //     _convertPostToV1(tree.post);

    //     tree.references[0] = _commentOrQuote(tree.post, commentQuoteFuzzBitmap, 0);
    //     tree.mirrors[0] = mirror(tree.references[0]);
    //     tree.references[1] = _commentOrQuote(tree.references[0], commentQuoteFuzzBitmap, 1);
    //     tree.mirrors[1] = mirror(tree.references[1]);
    //     tree.references[2] = _commentOrQuote(tree.references[1], commentQuoteFuzzBitmap, 2);
    //     tree.mirrors[2] = mirror(tree.references[2]);
    //     tree.references[3] = _commentOrQuote(tree.references[2], commentQuoteFuzzBitmap, 3);
    //     tree.mirrors[3] = mirror(tree.references[3]);

    //     tree.references[4] = _commentOrQuote(tree.post, commentQuoteFuzzBitmap, 4);
    //     tree.mirrors[4] = mirror(tree.references[4]);

    //     tree.mirrors[5] = mirror(tree.post);

    //     _convertToV1(tree.references[0], v1FuzzBitmap, 0);
    //     _convertToV1(tree.mirrors[0], v1FuzzBitmap, 1);
    //     _convertToV1(tree.references[1], v1FuzzBitmap, 2);
    //     _convertToV1(tree.mirrors[1], v1FuzzBitmap, 3);
    //     _convertToV1(tree.references[2], v1FuzzBitmap, 4);
    //     _convertToV1(tree.mirrors[2], v1FuzzBitmap, 5);
    //     _convertToV1(tree.references[3], v1FuzzBitmap, 6);
    //     _convertToV1(tree.mirrors[3], v1FuzzBitmap, 7);

    //     _convertToV1(tree.references[4], v1FuzzBitmap, 8);
    //     _convertToV1(tree.mirrors[4], v1FuzzBitmap, 9);

    //     _convertToV1(tree.mirrors[5], v1FuzzBitmap, 10);

    //     return tree;
    // }

    function _commentOrQuote(
        TestPublication memory testPub,
        uint256 commentQuoteFuzzBitmap,
        uint256 commentQuoteIndex
    ) internal returns (TestPublication memory) {
        uint256 commentQuoteFuzz = (commentQuoteFuzzBitmap >> (commentQuoteIndex)) & 1;
        if (commentQuoteFuzz == 0) {
            return _comment(testPub);
        } else {
            return _quote(testPub);
        }
    }

    function _post() internal returns (TestPublication memory) {
        testAccountId++;
        TestAccount memory publisher = _loadAccountAs(string.concat('TESTACCOUNT_', vm.toString(testAccountId)));
        Types.PostParams memory postParams = _getDefaultPostParams();
        postParams.profileId = publisher.profileId;

        vm.prank(publisher.owner);
        uint256 pubId = hub.post(postParams);

        console.log('Created POST: %s, %s', publisher.profileId, pubId);
        return TestPublication(publisher.profileId, pubId);
    }

    function _mirror(TestPublication memory testPub) internal returns (TestPublication memory) {
        testAccountId++;
        TestAccount memory publisher = _loadAccountAs(string.concat('TESTACCOUNT_', vm.toString(testAccountId)));
        Types.MirrorParams memory mirrorParams = _getDefaultMirrorParams();
        mirrorParams.profileId = publisher.profileId;
        mirrorParams.pointedPubId = testPub.pubId;
        mirrorParams.pointedProfileId = testPub.profileId;

        vm.prank(publisher.owner);
        uint256 pubId = hub.mirror(mirrorParams);

        console.log(
            'Created MIRROR: (%s) => (%s)',
            string.concat(vm.toString(publisher.profileId), ', ', vm.toString(pubId)),
            string.concat(vm.toString(testPub.profileId), ', ', vm.toString(testPub.pubId))
        );

        return TestPublication(publisher.profileId, pubId);
    }

    function _comment(TestPublication memory testPub) internal returns (TestPublication memory) {
        testAccountId++;
        TestAccount memory publisher = _loadAccountAs(string.concat('TESTACCOUNT_', vm.toString(testAccountId)));
        Types.CommentParams memory commentParams = _getDefaultCommentParams();

        commentParams.profileId = publisher.profileId;
        commentParams.pointedPubId = testPub.pubId;
        commentParams.pointedProfileId = testPub.profileId;

        vm.prank(publisher.owner);
        uint256 pubId = hub.comment(commentParams);

        console.log(
            'Created COMMENT: (%s) => (%s)',
            string.concat(vm.toString(publisher.profileId), ', ', vm.toString(pubId)),
            string.concat(vm.toString(testPub.profileId), ', ', vm.toString(testPub.pubId))
        );

        return TestPublication(publisher.profileId, pubId);
    }

    function _quote(TestPublication memory testPub) internal returns (TestPublication memory) {
        testAccountId++;
        TestAccount memory publisher = _loadAccountAs(string.concat('TESTACCOUNT_', vm.toString(testAccountId)));
        Types.QuoteParams memory quoteParams = _getDefaultQuoteParams();

        quoteParams.profileId = publisher.profileId;
        quoteParams.pointedPubId = testPub.pubId;
        quoteParams.pointedProfileId = testPub.profileId;

        vm.prank(publisher.owner);
        uint256 pubId = hub.quote(quoteParams);

        console.log(
            'Created QUOTE: (%s) => (%s)',
            string.concat(vm.toString(publisher.profileId), ', ', vm.toString(pubId)),
            string.concat(vm.toString(testPub.profileId), ', ', vm.toString(testPub.pubId))
        );

        return TestPublication(publisher.profileId, pubId);
    }

    ////// setup////
    /// create a big tree with all possible situations (V2 posts)
    /// We can use some custom data structure to simplify the tree handling, or just rely on "pointedTo" in pubs.
    ///
    ////// function replaceV1(depth) ///
    /// function that will convert a given depth of the V2 tree into V1 (starting from the root Post)
    ///
    ////// function testReferralsWorkV2() ///
    /// a function that takes each node of the V2 tree as target (except mirrors), and permutates with all possible referrers
    /// (or makes an array of all other nodes as referrers and passes then all together).
    /// Then it checks that the referral system works as expected (i.e. modules are called with the same array of referrals).
    ///
    ////// function testReferralsV1() ///
    /// a function that takes a V2 tree, and converts it to V1 tree gradually, starting with root Post, then level 1 from it, level 2, etc.
    /// At each step, it checks that you can only refer the direct link (pointing to), as this is the only thing possible in V1
    /// It does this by picking a random node from the tree as target, and then picking the rest of the nodes as referrers,
    /// and expecting them to be passed or failed, depending if they're direct or complex.
    ///

    // Negatives

    function testCannotExecuteOperationIf_ReferralProfileIdsPassedQty_DiffersFromPubIdsQty() public {
        // TODO - Errors.ArrayMismatch();
    }

    function testCannotPass_APublicationDoneByItself_AsReferrer() public {
        // TODO - Errors.InvalidReferrer();
    }

    function testCannotPass_Itself_AsReferrer() public {
        // TODO - Errors.InvalidReferrer();
    }

    function testCannotPass_UnexistentProfile_AsReferrer() public {
        // TODO - Errors.InvalidReferrer();
    }

    function testCannotPass_UnexistentPublication_AsReferrer() public {
        // TODO
    }

    function testCannotPass_AMirror_AsReferrer_IfNotPointingToTheTargetPublication() public {
        // TODO
    }

    function testCannotPass_AComment_AsReferrer_IfNotPointingToTheTargetPublication() public {
        // TODO
    }

    // Scenarios

    // This test might fail at some point when we check for duplicates!
    function testPassingDuplicatedReferralsIsAllowed() public {
        // TODO
    }
}

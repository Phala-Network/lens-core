import '@nomiclabs/hardhat-ethers';
import { expect } from 'chai';
import { CollectNFT__factory, FollowNFT__factory } from '../../../typechain-types';
import { MAX_UINT256, ZERO_ADDRESS } from '../../helpers/constants';
import { ERRORS } from '../../helpers/errors';
import {
  cancelWithPermitForAll,
  collectReturningTokenIds,
  getAbbreviation,
  getCollectWithSigParts,
  getTimestamp,
} from '../../helpers/utils';
import {
  lensHub,
  freeCollectModule,
  FIRST_PROFILE_ID,
  governance,
  makeSuiteCleanRoom,
  MOCK_PROFILE_HANDLE,
  MOCK_PROFILE_URI,
  MOCK_URI,
  testWallet,
  userAddress,
  userTwo,
  userTwoAddress,
  MOCK_FOLLOW_NFT_URI,
  abiCoder,
  user,
  oracleImpl,
} from '../../__setup.spec';
import { ethers } from 'hardhat';

makeSuiteCleanRoom('Collecting', function () {
  beforeEach(async function () {
    await expect(
      lensHub.connect(governance).whitelistCollectModule(freeCollectModule.address, true)
    ).to.not.be.reverted;
    await expect(
      lensHub.createProfile({
        to: userAddress,
        handle: MOCK_PROFILE_HANDLE,
        imageURI: MOCK_PROFILE_URI,
        followModule: ZERO_ADDRESS,
        followModuleInitData: [],
        followNFTURI: MOCK_FOLLOW_NFT_URI,
      })
    ).to.not.be.reverted;
    await expect(
      lensHub.post({
        profileId: FIRST_PROFILE_ID,
        contentURI: MOCK_URI,
        collectModule: freeCollectModule.address,
        collectModuleInitData: abiCoder.encode(['bool'], [true]),
        referenceModule: ZERO_ADDRESS,
        referenceModuleInitData: [],
      })
    ).to.not.be.reverted;
  });

  context('Generic', function () {
    context('Negatives', function () {
      it('UserTwo should fail to collect without being a follower', async function () {
        await expect(lensHub.connect(userTwo).collect(FIRST_PROFILE_ID, 1, [])).to.be.revertedWith(
          ERRORS.FOLLOW_INVALID
        );
      });

      it('user two should follow, then transfer the followNFT and fail to collect', async function () {
        await expect(lensHub.connect(userTwo).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        const followNftAddr = await lensHub.getFollowNFT(FIRST_PROFILE_ID);
        await expect(
          FollowNFT__factory.connect(followNftAddr, userTwo).transferFrom(
            userTwoAddress,
            userAddress,
            1
          )
        ).to.not.be.reverted;
        await expect(lensHub.connect(userTwo).collect(FIRST_PROFILE_ID, 1, [])).to.be.revertedWith(
          ERRORS.FOLLOW_INVALID
        );
      });
    });

    context('Scenarios', function () {
      it('Collecting should work if the collector is the publication owner even when he is not following himself and follow NFT was not deployed', async function () {
        await expect(lensHub.collect(FIRST_PROFILE_ID, 1, [])).to.not.be.reverted;
      });

      it('Collecting should work if the collector is the publication owner even when he is not following himself and follow NFT was deployed', async function () {
        await expect(lensHub.follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        const followNFT = FollowNFT__factory.connect(
          await lensHub.getFollowNFT(FIRST_PROFILE_ID),
          user
        );

        await expect(followNFT.transferFrom(userAddress, userTwoAddress, 1)).to.not.be.reverted;

        await expect(lensHub.collect(FIRST_PROFILE_ID, 1, [])).to.not.be.reverted;
      });

      it('Should return the expected token IDs when collecting publications', async function () {
        await expect(lensHub.connect(userTwo).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        await expect(
          lensHub.connect(testWallet).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;

        expect(
          await collectReturningTokenIds({
            vars: {
              profileId: FIRST_PROFILE_ID,
              pubId: 1,
              data: [],
            },
          })
        ).to.eq(1);

        expect(
          await collectReturningTokenIds({
            sender: userTwo,
            vars: {
              profileId: FIRST_PROFILE_ID,
              pubId: 1,
              data: [],
            },
          })
        ).to.eq(2);

        const nonce = (await lensHub.sigNonces(testWallet.address)).toNumber();
        const { v, r, s } = await getCollectWithSigParts(
          FIRST_PROFILE_ID,
          '1',
          [],
          nonce,
          MAX_UINT256
        );
        expect(
          await collectReturningTokenIds({
            vars: {
              collector: testWallet.address,
              profileId: FIRST_PROFILE_ID,
              pubId: '1',
              data: [],
              sig: {
                v,
                r,
                s,
                deadline: MAX_UINT256,
              },
            },
          })
        ).to.eq(3);

        expect(
          await collectReturningTokenIds({
            vars: {
              profileId: FIRST_PROFILE_ID,
              pubId: 1,
              data: [],
            },
          })
        ).to.eq(4);
      });

      it('UserTwo should follow, then collect, receive a collect NFT with the expected properties', async function () {
        await expect(lensHub.connect(userTwo).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        await expect(lensHub.connect(userTwo).collect(FIRST_PROFILE_ID, 1, [])).to.not.be.reverted;
        const timestamp = await getTimestamp();

        const collectNFTAddr = await lensHub.getCollectNFT(FIRST_PROFILE_ID, 1);
        expect(collectNFTAddr).to.not.eq(ZERO_ADDRESS);
        const collectNFT = CollectNFT__factory.connect(collectNFTAddr, userTwo);
        const id = await collectNFT.tokenOfOwnerByIndex(userTwoAddress, 0);
        const name = await collectNFT.name();
        const symbol = await collectNFT.symbol();
        const pointer = await collectNFT.getSourcePublicationPointer();
        const owner = await collectNFT.ownerOf(id);
        const mintTimestamp = await collectNFT.mintTimestampOf(id);
        const tokenData = await collectNFT.tokenDataOf(id);

        const expectedName = MOCK_PROFILE_HANDLE + '-Collect-' + '1';
        const expectedSymbol = getAbbreviation(MOCK_PROFILE_HANDLE) + '-Cl-' + '1';

        expect(id).to.eq(1);
        expect(name).to.eq(expectedName);
        expect(symbol).to.eq(expectedSymbol);
        expect(pointer[0]).to.eq(FIRST_PROFILE_ID);
        expect(pointer[1]).to.eq(1);
        expect(owner).to.eq(userTwoAddress);
        expect(tokenData.owner).to.eq(userTwoAddress);
        expect(tokenData.mintTimestamp).to.eq(timestamp);
        expect(mintTimestamp).to.eq(timestamp);
      });

      it('UserTwo should follow, then mirror, then collect on their mirror, receive a collect NFT with expected properties', async function () {
        await expect(lensHub.connect(userTwo).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        const secondProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(userTwo).createProfile({
            to: userTwoAddress,
            handle: 'mockhandle',
            imageURI: MOCK_PROFILE_URI,
            followModule: ZERO_ADDRESS,
            followModuleInitData: [],
            followNFTURI: MOCK_FOLLOW_NFT_URI,
          })
        ).to.not.be.reverted;

        await expect(
          lensHub.connect(userTwo).mirror({
            profileId: secondProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: 1,
            referenceModuleData: [],
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;

        await expect(lensHub.connect(userTwo).collect(secondProfileId, 1, [])).to.not.be.reverted;

        const collectNFTAddr = await lensHub.getCollectNFT(FIRST_PROFILE_ID, 1);
        expect(collectNFTAddr).to.not.eq(ZERO_ADDRESS);
        const collectNFT = CollectNFT__factory.connect(collectNFTAddr, userTwo);
        const id = await collectNFT.tokenOfOwnerByIndex(userTwoAddress, 0);
        const name = await collectNFT.name();
        const symbol = await collectNFT.symbol();
        const pointer = await collectNFT.getSourcePublicationPointer();

        const expectedName = MOCK_PROFILE_HANDLE + '-Collect-' + '1';
        const expectedSymbol = getAbbreviation(MOCK_PROFILE_HANDLE) + '-Cl-' + '1';
        expect(id).to.eq(1);
        expect(name).to.eq(expectedName);
        expect(symbol).to.eq(expectedSymbol);
        expect(pointer[0]).to.eq(FIRST_PROFILE_ID);
        expect(pointer[1]).to.eq(1);
      });

      it('UserTwo should follow, then mirror, mirror their mirror then collect on their latest mirror, receive a collect NFT with expected properties', async function () {
        await expect(lensHub.connect(userTwo).follow([FIRST_PROFILE_ID], [[]])).to.not.be.reverted;
        const secondProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(userTwo).createProfile({
            to: userTwoAddress,
            handle: 'mockhandle',
            imageURI: MOCK_PROFILE_URI,
            followModule: ZERO_ADDRESS,
            followModuleInitData: [],
            followNFTURI: MOCK_FOLLOW_NFT_URI,
          })
        ).to.not.be.reverted;

        await expect(
          lensHub.connect(userTwo).mirror({
            profileId: secondProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: 1,
            referenceModuleData: [],
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;

        await expect(
          lensHub.connect(userTwo).mirror({
            profileId: secondProfileId,
            profileIdPointed: secondProfileId,
            pubIdPointed: 1,
            referenceModuleData: [],
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;

        await expect(lensHub.connect(userTwo).collect(secondProfileId, 2, [])).to.not.be.reverted;

        const collectNFTAddr = await lensHub.getCollectNFT(FIRST_PROFILE_ID, 1);
        expect(collectNFTAddr).to.not.eq(ZERO_ADDRESS);
        const collectNFT = CollectNFT__factory.connect(collectNFTAddr, userTwo);
        const id = await collectNFT.tokenOfOwnerByIndex(userTwoAddress, 0);
        const name = await collectNFT.name();
        const symbol = await collectNFT.symbol();
        const pointer = await collectNFT.getSourcePublicationPointer();

        const expectedName = MOCK_PROFILE_HANDLE + '-Collect-' + '1';
        const expectedSymbol = getAbbreviation(MOCK_PROFILE_HANDLE) + '-Cl-' + '1';
        expect(id).to.eq(1);
        expect(name).to.eq(expectedName);
        expect(symbol).to.eq(expectedSymbol);
        expect(pointer[0]).to.eq(FIRST_PROFILE_ID);
        expect(pointer[1]).to.eq(1);
      });
    });

    context.only('Momoka', function() {
      it('Should allow to free-collect a Momoka post with oracle data', async function () {
        const momokaId = ethers.BigNumber.from(0x46a30696);
        const refPubId = ethers.BigNumber.from(1);
        const pubId =  momokaId.shl(128).or(refPubId);
        const signer = new ethers.Wallet('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80', ethers.provider);
        const attestation = await simulateOracleAttestation(
          FIRST_PROFILE_ID.toString(),
          pubId.toString(),
          'ar://s7-KUGt9F0TuJ4xTP01kbybqz0QLsk7NKp4zy4day1M',
          '0x',
          oracleImpl.address,
          signer
        );

        const tx = lensHub.connect(userTwo).daCollect(FIRST_PROFILE_ID, pubId, attestation, []);
        await expect(tx).to.not.be.reverted;

        const collectNFTAddr = await lensHub.getCollectNFT(FIRST_PROFILE_ID, pubId);
        expect(collectNFTAddr).to.not.eq(ZERO_ADDRESS);
        const collectNFT = CollectNFT__factory.connect(collectNFTAddr, userTwo);
        const id = await collectNFT.tokenOfOwnerByIndex(userTwoAddress, 0);
        const name = await collectNFT.name();
        const symbol = await collectNFT.symbol();
        const pointer = await collectNFT.getSourcePublicationPointer();

        const expectedName = `${MOCK_PROFILE_HANDLE}-Collect-1-DA-0x46a30696`;
        const expectedSymbol = `${getAbbreviation(MOCK_PROFILE_HANDLE)}-Cl-1-DA-0x46a30696`;
        expect(id).to.eq(1);
        expect(name).to.eq(expectedName);
        expect(symbol).to.eq(expectedSymbol);
        expect(pointer[0]).to.eq(FIRST_PROFILE_ID);
        expect(pointer[1]).to.eq(pubId);
      });

      it('can collect 0x01 post', async function () {
        const momokaId = ethers.BigNumber.from(0xeb395e21);
        const refPubId = ethers.BigNumber.from(0x01ef);
        const pubId =  momokaId.shl(128).or(refPubId);
        const attestation = '0x00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000280000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000eb395e21000000000000000000000000000001ef0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000eb395e21000000000000000000000000000001ef00000000000000000000000023b9467334beb345aaa6fd1545538f3d54436e9600000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000003061723a2f2f66524d5635647345456c6d5f5f766c50666a5270555f5150514c324f5a7139673562595f704461495a6d30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004164cd5e50c72a6b14f8d3a6f374a6d3cd52af8ece2cda282bbbf1ab4c30623690153a9361c42124d48f8f925ea5c22cd585bd70f8fde0a2cd655ff7f365eec0cd1c00000000000000000000000000000000000000000000000000000000000000';
        const tx = lensHub.connect(userTwo).daCollect(FIRST_PROFILE_ID, pubId, attestation, []);
        // await expect(tx).to.not.be.reverted;
        await expect(tx).to.be.revertedWith('abc');

        const collectNFTAddr = await lensHub.getCollectNFT(FIRST_PROFILE_ID, pubId);
        expect(collectNFTAddr).to.not.eq(ZERO_ADDRESS);
        const collectNFT = CollectNFT__factory.connect(collectNFTAddr, userTwo);
        const id = await collectNFT.tokenOfOwnerByIndex(userTwoAddress, 0);
        const name = await collectNFT.name();
        const symbol = await collectNFT.symbol();
        const pointer = await collectNFT.getSourcePublicationPointer();

        const expectedName = `${MOCK_PROFILE_HANDLE}-Collect-1-DA-0xeb395e21`;
        const expectedSymbol = `${getAbbreviation(MOCK_PROFILE_HANDLE)}-Cl-1-DA-0xeb395e21`;
        expect(id).to.eq(1);
        expect(name).to.eq(expectedName);
        expect(symbol).to.eq(expectedSymbol);
        expect(pointer[0]).to.eq(FIRST_PROFILE_ID);
        expect(pointer[1]).to.eq(pubId);
      });
    });
  });

  context.skip('Meta-tx', function () {
    context('Negatives', function () {
      it('TestWallet should fail to collect with sig with signature deadline mismatch', async function () {
        const nonce = (await lensHub.sigNonces(testWallet.address)).toNumber();

        const { v, r, s } = await getCollectWithSigParts(FIRST_PROFILE_ID, '1', [], nonce, '0');

        await expect(
          lensHub.collectWithSig({
            collector: testWallet.address,
            profileId: FIRST_PROFILE_ID,
            pubId: '1',
            data: [],
            sig: {
              v,
              r,
              s,
              deadline: MAX_UINT256,
            },
          })
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });

      it('TestWallet should fail to collect with sig with invalid deadline', async function () {
        const nonce = (await lensHub.sigNonces(testWallet.address)).toNumber();

        const { v, r, s } = await getCollectWithSigParts(FIRST_PROFILE_ID, '1', [], nonce, '0');

        await expect(
          lensHub.collectWithSig({
            collector: testWallet.address,
            profileId: FIRST_PROFILE_ID,
            pubId: '1',
            data: [],
            sig: {
              v,
              r,
              s,
              deadline: '0',
            },
          })
        ).to.be.revertedWith(ERRORS.SIGNATURE_EXPIRED);
      });

      it('TestWallet should fail to collect with sig with invalid nonce', async function () {
        const nonce = (await lensHub.sigNonces(testWallet.address)).toNumber();

        const { v, r, s } = await getCollectWithSigParts(
          FIRST_PROFILE_ID,
          '1',
          [],
          nonce + 1,
          MAX_UINT256
        );

        await expect(
          lensHub.collectWithSig({
            collector: testWallet.address,
            profileId: FIRST_PROFILE_ID,
            pubId: '1',
            data: [],
            sig: {
              v,
              r,
              s,
              deadline: MAX_UINT256,
            },
          })
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });

      it('TestWallet should fail to collect with sig without being a follower', async function () {
        const nonce = (await lensHub.sigNonces(testWallet.address)).toNumber();

        const { v, r, s } = await getCollectWithSigParts(
          FIRST_PROFILE_ID,
          '1',
          [],
          nonce,
          MAX_UINT256
        );

        await expect(
          lensHub.collectWithSig({
            collector: testWallet.address,
            profileId: FIRST_PROFILE_ID,
            pubId: '1',
            data: [],
            sig: {
              v,
              r,
              s,
              deadline: MAX_UINT256,
            },
          })
        ).to.be.revertedWith(ERRORS.FOLLOW_INVALID);
      });

      it('TestWallet should sign attempt to collect with sig, cancel via empty permitForAll, fail to collect with sig', async function () {
        await expect(
          lensHub.connect(testWallet).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;

        const nonce = (await lensHub.sigNonces(testWallet.address)).toNumber();

        const { v, r, s } = await getCollectWithSigParts(
          FIRST_PROFILE_ID,
          '1',
          [],
          nonce,
          MAX_UINT256
        );

        await cancelWithPermitForAll();

        await expect(
          lensHub.collectWithSig({
            collector: testWallet.address,
            profileId: FIRST_PROFILE_ID,
            pubId: '1',
            data: [],
            sig: {
              v,
              r,
              s,
              deadline: MAX_UINT256,
            },
          })
        ).to.be.revertedWith(ERRORS.SIGNATURE_INVALID);
      });
    });

    context('Scenarios', function () {
      it('TestWallet should follow, then collect with sig, receive a collect NFT with expected properties', async function () {
        await expect(
          lensHub.connect(testWallet).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;

        const nonce = (await lensHub.sigNonces(testWallet.address)).toNumber();

        const { v, r, s } = await getCollectWithSigParts(
          FIRST_PROFILE_ID,
          '1',
          [],
          nonce,
          MAX_UINT256
        );

        await expect(
          lensHub.collectWithSig({
            collector: testWallet.address,
            profileId: FIRST_PROFILE_ID,
            pubId: '1',
            data: [],
            sig: {
              v,
              r,
              s,
              deadline: MAX_UINT256,
            },
          })
        ).to.not.be.reverted;

        const collectNFTAddr = await lensHub.getCollectNFT(FIRST_PROFILE_ID, 1);
        expect(collectNFTAddr).to.not.eq(ZERO_ADDRESS);
        const collectNFT = CollectNFT__factory.connect(collectNFTAddr, userTwo);
        const id = await collectNFT.tokenOfOwnerByIndex(testWallet.address, 0);
        const name = await collectNFT.name();
        const symbol = await collectNFT.symbol();
        const pointer = await collectNFT.getSourcePublicationPointer();

        const expectedName = MOCK_PROFILE_HANDLE + '-Collect-' + '1';
        const expectedSymbol = getAbbreviation(MOCK_PROFILE_HANDLE) + '-Cl-' + '1';
        expect(id).to.eq(1);
        expect(name).to.eq(expectedName);
        expect(symbol).to.eq(expectedSymbol);
        expect(pointer[0]).to.eq(FIRST_PROFILE_ID);
        expect(pointer[1]).to.eq(1);
      });

      it('TestWallet should follow, mirror, then collect with sig on their mirror', async function () {
        await expect(
          lensHub.connect(testWallet).follow([FIRST_PROFILE_ID], [[]])
        ).to.not.be.reverted;
        const secondProfileId = FIRST_PROFILE_ID + 1;
        await expect(
          lensHub.connect(testWallet).createProfile({
            to: testWallet.address,
            handle: 'mockhandle',
            imageURI: MOCK_PROFILE_URI,
            followModule: ZERO_ADDRESS,
            followModuleInitData: [],
            followNFTURI: MOCK_FOLLOW_NFT_URI,
          })
        ).to.not.be.reverted;

        await expect(
          lensHub.connect(testWallet).mirror({
            profileId: secondProfileId,
            profileIdPointed: FIRST_PROFILE_ID,
            pubIdPointed: 1,
            referenceModuleData: [],
            referenceModule: ZERO_ADDRESS,
            referenceModuleInitData: [],
          })
        ).to.not.be.reverted;

        const nonce = (await lensHub.sigNonces(testWallet.address)).toNumber();

        const { v, r, s } = await getCollectWithSigParts(
          secondProfileId.toString(),
          '1',
          [],
          nonce,
          MAX_UINT256
        );

        await expect(
          lensHub.collectWithSig({
            collector: testWallet.address,
            profileId: secondProfileId,
            pubId: '1',
            data: [],
            sig: {
              v,
              r,
              s,
              deadline: MAX_UINT256,
            },
          })
        ).to.not.be.reverted;

        const collectNFTAddr = await lensHub.getCollectNFT(FIRST_PROFILE_ID, 1);
        expect(collectNFTAddr).to.not.eq(ZERO_ADDRESS);
        const collectNFT = CollectNFT__factory.connect(collectNFTAddr, userTwo);
        const id = await collectNFT.tokenOfOwnerByIndex(testWallet.address, 0);
        const name = await collectNFT.name();
        const symbol = await collectNFT.symbol();
        const pointer = await collectNFT.getSourcePublicationPointer();

        const expectedName = MOCK_PROFILE_HANDLE + '-Collect-' + '1';
        const expectedSymbol = getAbbreviation(MOCK_PROFILE_HANDLE) + '-Cl-' + '1';
        expect(id).to.eq(1);
        expect(name).to.eq(expectedName);
        expect(symbol).to.eq(expectedSymbol);
        expect(pointer[0]).to.eq(FIRST_PROFILE_ID);
        expect(pointer[1]).to.eq(1);
      });
    });
  });
});

import { Wallet } from 'ethers';

interface MetaTxData {
  from: string;
  nonce: number;
  data: string;
};
type RollupParams = [string, string];

async function signMetaTx(signer: Wallet, contractAddress: string, value: MetaTxData) {
  // All properties on a domain are optional
  const domain = {
    name: 'PhatRollupMetaTxReceiver',
    version: '0.0.1',
    chainId: 31337,  // hardhat chain id
    verifyingContract: contractAddress
  };
  const types = {
    ForwardRequest: [
        { name: 'from', type: 'address' },
        { name: 'nonce', type: 'uint256' },
        { name: 'data', type: 'bytes' }
    ]
  };
  return await signer._signTypedData(domain, types, value);
}

async function metaTx(rollupParams: RollupParams, signer: Wallet, nonce: number, contractAddress: string): Promise<[MetaTxData, string]> {
  const data = ethers.utils.defaultAbiCoder.encode(
    ['bytes', 'bytes'],
    rollupParams,
  );
  const metaTxData = {
    from: signer.address,
    nonce,
    data,
  };
  const metaTxSig = await signMetaTx(signer, contractAddress, metaTxData);
  return [metaTxData, metaTxSig]
}


async function simulateOracleAttestation(profileId: string, pubId: string, contentURI: string, moduleData: string, oracleImplAddress: string, attestor: Wallet) {
  // Oracle response
  const req = '0x00000000'
  const collectModule = freeCollectModule.address;
  const collectData = ethers.utils.defaultAbiCoder.encode(
    ['bytes4', 'uint256', 'uint256', 'uint256', 'uint256', 'address', 'string'],
    [req, profileId, pubId, profileId, pubId, collectModule, contentURI],
  );

  const [metaTxData, sig] = await metaTx([collectData, moduleData], attestor, 0, oracleImplAddress);

  const encodedData = ethers.utils.defaultAbiCoder.encode(
    ['tuple(address,uint256,bytes)', 'bytes'],
    [[metaTxData.from, metaTxData.nonce, metaTxData.data], sig],
  );

  console.log({
    metaTxData,
    sig,
    encodedData,
  });
  return encodedData;
}
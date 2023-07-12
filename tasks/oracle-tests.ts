import '@nomiclabs/hardhat-ethers';
import { hexlify, keccak256, RLP } from 'ethers/lib/utils';
import fs from 'fs';
import { task } from 'hardhat/config';
import {
  LensHub__factory,
  ApprovalFollowModule__factory,
  CollectNFT__factory,
  Currency__factory,
  FreeCollectModule__factory,
  FeeCollectModule__factory,
  FeeFollowModule__factory,
  FollowerOnlyReferenceModule__factory,
  FollowNFT__factory,
  InteractionLogic__factory,
  LimitedFeeCollectModule__factory,
  LimitedTimedFeeCollectModule__factory,
  ModuleGlobals__factory,
  PublishingLogic__factory,
  RevertCollectModule__factory,
  TimedFeeCollectModule__factory,
  TransparentUpgradeableProxy__factory,
  ProfileTokenURILogic__factory,
  LensPeriphery__factory,
  UIDataProvider__factory,
  ProfileFollowModule__factory,
  RevertFollowModule__factory,
  ProfileCreationProxy__factory,
} from '../typechain-types';
import { deployContract, waitForTx } from './helpers/utils';
import { ProtocolState, initEnv, getAddrs, ZERO_ADDRESS } from './helpers/utils';
import { CreateProfileDataStruct, PostDataStruct } from '../typechain-types/LensHub';

// const TREASURY_FEE_BPS = 50;
// const LENS_HUB_NFT_NAME = 'Lens Protocol Profiles';
// const LENS_HUB_NFT_SYMBOL = 'LPP';

task('unpause', 'unpause the protocol').setAction(async ({}, hre) => {
  const [governance] = await initEnv(hre);
  const addrs = getAddrs();
  const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], governance);
  await waitForTx(lensHub.setState(ProtocolState.Unpaused));
})

task('create-profile', 'creates a profile').setAction(async ({}, hre) => {
  const [governance, , user] = await initEnv(hre);
  const addrs = getAddrs();
  const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], governance);

  await waitForTx(lensHub.whitelistProfileCreator(user.address, true));

  const inputStruct: CreateProfileDataStruct = {
    to: user.address,
    handle: 'zer0dot',
    imageURI: 'https://ipfs.io/ipfs/QmY9dUwYu67puaWBMxRKW98LPbXCznPwHUbhX5NeWnCJbX',
    followModule: ZERO_ADDRESS,
    followModuleInitData: [],
    followNFTURI: 'https://ipfs.io/ipfs/QmTFLSXdEQ6qsSzaXaCSNtiv6wA56qq87ytXJ182dXDQJS',
  };

  await waitForTx(lensHub.connect(user).createProfile(inputStruct));

  console.log(`Total supply (should be 1): ${await lensHub.totalSupply()}`);
  console.log(
    `Profile owner: ${await lensHub.ownerOf(1)}, user address (should be the same): ${user.address}`
  );
  console.log(`Profile ID by handle: ${await lensHub.getProfileIdByHandle('zer0dot')}`);
});


task('post', 'publishes a post').setAction(async ({}, hre) => {
  const [governance, , user] = await initEnv(hre);
  const addrs = getAddrs();
  const freeCollectModuleAddr = addrs['free collect module'];
  const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], governance);

  await waitForTx(lensHub.whitelistCollectModule(freeCollectModuleAddr, true));

  const defaultAbiCoder = hre.ethers.utils.defaultAbiCoder;
  const inputStruct: PostDataStruct = {
    profileId: 1,
    contentURI: 'https://ipfs.io/ipfs/Qmby8QocUU2sPZL46rZeMctAuF5nrCc7eR1PPkooCztWPz',
    collectModule: freeCollectModuleAddr,
    collectModuleInitData: defaultAbiCoder.encode(['bool'], [true]),
    referenceModule: ZERO_ADDRESS,
    referenceModuleInitData: [],
  };

  await waitForTx(lensHub.connect(user).post(inputStruct));
  console.log(await lensHub.getPub(1, 1));
});

task('collect', 'collects a post').setAction(async ({}, hre) => {
  const [, , user] = await initEnv(hre);
  const addrs = getAddrs();
  const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], user);

  await waitForTx(lensHub.collect(1, 1, []));

  const collectNFTAddr = await lensHub.getCollectNFT(1, 1);
  const collectNFT = CollectNFT__factory.connect(collectNFTAddr, user);

  const publicationContentURI = await lensHub.getContentURI(1, 1);
  const totalSupply = await collectNFT.totalSupply();
  const ownerOf = await collectNFT.ownerOf(1);
  const collectNFTURI = await collectNFT.tokenURI(1);

  console.log(`Collect NFT total supply (should be 1): ${totalSupply}`);
  console.log(
    `Collect NFT owner of ID 1: ${ownerOf}, user address (should be the same): ${user.address}`
  );
  console.log(
    `Collect NFT URI: ${collectNFTURI}, publication content URI (should be the same): ${publicationContentURI}`
  );
});

task('collect-momoka', 'collects a Momoka post').setAction(async ({}, hre) => {
  const [, , user] = await initEnv(hre);
  const addrs = getAddrs();
  const lensHub = LensHub__factory.connect(addrs['lensHub proxy'], user);

  const ethers = hre.ethers;
  const profileId = 0x01;
  const momokaId = ethers.BigNumber.from(0xbd1f8159);
  const refPubId = ethers.BigNumber.from(0x01ef);
  const pubId = momokaId.shl(128).or(refPubId);
  const publicationId = '0x01-0x01ef-DA-bd1f8159';

  console.log('Starting collect a momoka post (dry run)');
  const attestation = await getAttestation(publicationId);
  console.log({ attestation });
  const moduleData = '0x';
  const est = await lensHub.estimateGas.daCollect(profileId, pubId, attestation, moduleData);
  console.log('Dry run result:', est);
  if (false) {
    // early return
    return;
  }

  console.log('Starting collect a momoka post');
  await waitForTx(lensHub.daCollect(profileId, pubId, attestation, moduleData));
  console.log('Collected');

  const collectNFTAddr = await lensHub.getCollectNFT(profileId, pubId);
  console.log({ collectNFTAddr });
  const collectNFT = CollectNFT__factory.connect(collectNFTAddr, user);

  const publicationContentURI = await lensHub.getContentURI(profileId, pubId);
  console.log({ publicationContentURI });
  const totalSupply = await collectNFT.totalSupply();
  console.log({ totalSupply });
  const ownerOf = await collectNFT.ownerOf(totalSupply);
  const collectNFTURI = await collectNFT.tokenURI(totalSupply);
  console.log({ collectNFTURI });

  console.log(`Collect NFT total supply (should be >=1): ${totalSupply}`);
  console.log(
    `Collect NFT owner of ID ${totalSupply}: ${ownerOf}, user address (should be the same): ${user.address}`
  );
  console.log(
    `Collect NFT URI: ${collectNFTURI}, publication content URI (should be the same): ${publicationContentURI}`
  );
});

import { ApiPromise } from '@polkadot/api';
import { WsProvider } from '@polkadot/rpc-provider';
import { Keyring } from '@polkadot/api';
import * as Phala from '@phala/sdk';
import MomokaOracleAbi from './abis/momoka_publication.json';
import { stringToHex, u8aToHex } from "@polkadot/util";

async function getAttestation(fullPubId: string): Promise<string> {
  const provider = new WsProvider('wss://poc5.phala.network/ws');
  const api = new ApiPromise(Phala.options({ provider }));
  await api.isReady;

  const keyring = new Keyring({ type: 'sr25519' });
  const pair = keyring.addFromUri('//Alice');
  const address = pair.address;
  const cert = await Phala.signCertificate({ pair, api });

  const contractId = '0x03891149872fb94190127b1a4ed63d874b0cad5171b1c2a0244e9f94a4aecf6e';
  const registry = await Phala.OnChainRegistry.create(api);
  const contractKey = await registry.getContractKeyOrFail(contractId);
  
  const oracle = new Phala.PinkContractPromise(api, registry, MomokaOracleAbi, contractId, contractKey);

  const hexStr = stringToHex(fullPubId);
  // @ts-ignore
  const result: any = await oracle.query.checkLensPublication(address, {cert}, hexStr, true, true);
  if (!result.output.isOk || !result.output.asOk.isOk) {
      console.log('Failed:', result.output.toHuman());
  }
  const attestation = u8aToHex(result.output.asOk.asOk);
  return attestation;
}

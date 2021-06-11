import { ethers } from "hardhat";
import { Signer } from "ethers";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import "@openzeppelin/test-helpers";
import { advanceBlockTo } from "./helpers/time";
import {
  BundleToken,
  BundleToken__factory,
  BundleLock,
  BundleLock__factory
} from "../typechain";
import { time } from "console";

chai.use(solidity);
const { expect } = chai;

describe("BundleLock", () => {
  // Contract as Signer
  let bundleTokenAsAlice: BundleToken;
  let bundleLockAsAlice: BundleLock;
  let bundleTokenAsDeployer: BundleToken;
  let bundleLockAsDeployer: BundleLock;

  // Accounts
  let deployer: Signer;
  let alice: Signer;

  let bundleToken: BundleToken;
  let bundleLock: BundleLock;

  beforeEach(async() => {
    [deployer, alice] = await ethers.getSigners();

    // Deploy BDL
    const BundleToken = (await ethers.getContractFactory(
      "BundleToken",
      deployer
    )) as BundleToken__factory;
    bundleToken = await BundleToken.deploy(132, 137);
    await bundleToken.deployed();

    // Deploy lock
    const BundleLock = (await ethers.getContractFactory(
        "BundleLock",
        deployer
    )) as BundleLock__factory;
    bundleLock = await BundleLock.deploy(bundleToken.address, 100);

    bundleTokenAsAlice = BundleToken__factory.connect(bundleToken.address, alice);
    bundleLockAsAlice = BundleLock__factory.connect(bundleLock.address, alice);

    bundleTokenAsDeployer = BundleToken__factory.connect(bundleToken.address, deployer);
    bundleLockAsDeployer = BundleLock__factory.connect(bundleLock.address, deployer);
  });

  context('when interacting as user', async() => {
    it('should set tiers properly', async() => {
        // Initialize tiers
        expect(await bundleLock.getTier(await alice.getAddress())).to.be.bignumber.and.eq('0');
        await bundleLockAsDeployer.pushTier(ethers.utils.parseEther('10'));
        expect(await bundleLock.getLockThreshold(1)).to.be.bignumber.and.eq(ethers.utils.parseEther('10'));
        await bundleLockAsDeployer.pushTier(ethers.utils.parseEther('100'));
        expect(await bundleLock.getLockThreshold(2)).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
        await bundleLockAsDeployer.setLockThreshold(1, ethers.utils.parseEther('20'));
        expect(await bundleLock.getLockThreshold(1)).to.be.bignumber.and.eq(ethers.utils.parseEther('20'));

        // Set out of bounds tier
        await expect(bundleLockAsDeployer.setLockThreshold(3, ethers.utils.parseEther('2000'))).to.be.revertedWith("ERR_OUT_OF_BOUNDS");

        // Remove a tier
        await bundleLockAsDeployer.popTier();
        await expect(bundleLock.getLockThreshold(2)).to.be.revertedWith("ERR_OUT_OF_BOUNDS");
    });

    it('should accept deposits and withdrawals correctly', async() => {
        // Mint tokens for alice
        await bundleTokenAsDeployer.mint((await alice.getAddress()), ethers.utils.parseEther('100'));
        expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));

        await bundleLockAsDeployer.pushTier(ethers.utils.parseEther('10'));
        await bundleLockAsDeployer.pushTier(ethers.utils.parseEther('100'));

        // Alice deposits tokens
        await bundleTokenAsAlice.approve(bundleLock.address, ethers.utils.parseEther('100'));
        await bundleLockAsAlice.deposit(ethers.utils.parseEther('100'));
        let lock = (await ethers.provider.getBlockNumber()) + 100;
        expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('0'));
        expect(await bundleToken.balanceOf(bundleLock.address)).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
        expect(await bundleLock.getTier(await alice.getAddress())).to.be.bignumber.and.eq('2');
        expect(await bundleLock.getBundleBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
        expect(await bundleLock.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
        expect(await bundleLock.getLock(await alice.getAddress())).to.be.bignumber.and.eq(lock);
        
        // Set tier
        await bundleLockAsDeployer.setLockThreshold(2, ethers.utils.parseEther('200'));
        expect(await bundleLock.getLockThreshold(2)).to.be.bignumber.and.eq(ethers.utils.parseEther('200'));
        expect(await bundleLock.getTier(await alice.getAddress())).to.be.bignumber.and.eq('1');

        // Alice attempts to withdraw
        await expect(bundleLockAsAlice.withdraw(ethers.utils.parseEther('100'))).to.be.revertedWith("ERR_LOCK");
        await advanceBlockTo(lock);
        await bundleLockAsAlice.withdraw(ethers.utils.parseEther('100'));
        expect(await bundleLock.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('0'));
        expect(await bundleLock.getLock(await alice.getAddress())).to.be.bignumber.and.eq(lock);
        expect(await bundleLock.getBundleBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('0'));
        expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
    });
  });
});

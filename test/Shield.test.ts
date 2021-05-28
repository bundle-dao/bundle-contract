import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import "@openzeppelin/test-helpers";
import {
  BundleToken,
  BundleToken__factory,
  Minter,
  Minter__factory,
  MockERC20,
  MockERC20__factory,
  Shield,
  Shield__factory,
  Timelock,
  Timelock__factory,
} from "../typechain";
import * as TimeHelpers from "./helpers/time";

chai.use(solidity);
const { expect } = chai;

describe("Shield", () => {
  const BUNDLE_REWARD_PER_BLOCK = ethers.utils.parseEther('5000');
  const BONUS_LOCK_RATIO = 9000;

  // Contract as Signer
  let timelockAsDev: Timelock;

  // Accounts
  let deployer: Signer;
  let alice: Signer;
  let bob: Signer;
  let dev: Signer;

  // Contracts
  let bundleToken: BundleToken;
  let minter: Minter;
  let shield: Shield;
  let stakingTokens: MockERC20[];
  let timelock: Timelock;

  beforeEach(async() => {
    [deployer, alice, bob, dev] = await ethers.getSigners();

    // Setup Minter contract
    // Deploy BDL
    const BundleToken = (await ethers.getContractFactory(
      "BundleToken",
      deployer
    )) as BundleToken__factory;
    bundleToken = await BundleToken.deploy(132, 1000);
    await bundleToken.deployed();

    const Minter = (await ethers.getContractFactory(
      "Minter",
      deployer
    )) as Minter__factory;
    minter = await Minter.deploy(
      bundleToken.address, (await dev.getAddress()), BUNDLE_REWARD_PER_BLOCK, 0
    )
    await minter.deployed();

    await bundleToken.transferOwnership(minter.address);

    const Timelock = (await ethers.getContractFactory(
      "Timelock",
      deployer
    )) as Timelock__factory;
    timelock = await Timelock.deploy(await dev.getAddress(), '259200');
    await timelock.deployed();

    const Shield = (await ethers.getContractFactory(
      "Shield",
      deployer
    )) as Shield__factory;
    shield = await Shield.deploy(timelock.address, minter.address);
    await shield.deployed();

    stakingTokens = new Array();
    for(let i = 0; i < 4; i++) {
      const MockERC20 = (await ethers.getContractFactory(
        "MockERC20",
        deployer
      )) as MockERC20__factory;
      const mockERC20 = await upgrades.deployProxy(MockERC20, [`STOKEN${i}`, `STOKEN${i}`]) as MockERC20;
      await mockERC20.deployed();
      stakingTokens.push(mockERC20);
    }

    timelockAsDev = Timelock__factory.connect(timelock.address, dev);
  });

  context("when migrate Minter's owner from Timelock to Shield + Timelock", async() => {
    beforeEach(async() => {
      await minter.transferOwnership(timelock.address);

      expect(await minter.owner()).to.be.eq(timelock.address);
      expect(await shield.owner()).to.be.eq(timelock.address);
    });

    it('should revert when non owner to interact with Shield', async() => {
      await expect(
        shield.setRewardsPerBlock(ethers.utils.parseEther('1'))
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        shield.setBonus(1, 500, BONUS_LOCK_RATIO)
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        shield.mintWarchest(await dev.getAddress(), ethers.utils.parseEther('1'))
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        shield.addPool(1, stakingTokens[0].address, false)
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        shield.setPool(1, 100, false)
      ).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('should revert when adjust param through Timelock + Shield when migration has not been done', async() => {
      const eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'addPool(uint256,address,bool)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'address', 'bool'],
          [100, stakingTokens[0].address, false]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await expect(timelockAsDev.executeTransaction(
        shield.address, '0', 'addPool(uint256,address,bool)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'address', 'bool'],
          [100, stakingTokens[0].address, false]), eta
      )).to.be.revertedWith('Ownable: caller is not the owner');
    })

    it('should migrate successfully', async() => {
      const eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        minter.address, '0', 'transferOwnership(address)',
        ethers.utils.defaultAbiCoder.encode(
          ['address'],
          [shield.address]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await timelockAsDev.executeTransaction(
        minter.address, '0', 'transferOwnership(address)',
        ethers.utils.defaultAbiCoder.encode(
          ['address'],
          [shield.address]), eta
      );

      expect(await minter.owner()).to.be.eq(shield.address);
    })
  });

  context("when adjust Minter's params via Shield + Timelock", async() => {
    beforeEach(async() => {
      await minter.transferOwnership(shield.address);

      expect(await minter.owner()).to.be.eq(shield.address);
      expect(await shield.owner()).to.be.eq(timelock.address);
    });

    it('should add new pool when Timelock is passed ETA', async() => {
      const eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'addPool(uint256,address,bool)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'address', 'bool'],
          [100, stakingTokens[0].address, false]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await timelockAsDev.executeTransaction(
        shield.address, '0', 'addPool(uint256,address,bool)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'address', 'bool'],
          [100, stakingTokens[0].address, false]), eta
      );

      expect((await minter.poolInfo(0)).allocPoint).to.be.bignumber.eq(100);
      expect((await minter.poolInfo(0)).stakeToken).to.be.eq(stakingTokens[0].address);
    });

    it('should set pool on existed pool when Timelock is passed ETA', async() => {
      let eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'addPool(uint256,address,bool)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'address', 'bool'],
          [100, stakingTokens[0].address, false]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await timelockAsDev.executeTransaction(
        shield.address, '0', 'addPool(uint256,address,bool)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'address', 'bool'],
          [100, stakingTokens[0].address, false]), eta
      );

      expect((await minter.poolInfo(0)).allocPoint).to.be.bignumber.eq(100);
      expect((await minter.poolInfo(0)).stakeToken).to.be.eq(stakingTokens[0].address);

      eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'setPool(uint256,uint256,bool)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'uint256', 'bool'],
          [0, 200, false]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await timelockAsDev.executeTransaction(
        shield.address, '0', 'setPool(uint256,uint256,bool)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'uint256', 'bool'],
          [0, 200, false]), eta
      );

      expect((await minter.poolInfo(0)).allocPoint).to.be.bignumber.eq(200);
      expect((await minter.poolInfo(0)).stakeToken).to.be.eq(stakingTokens[0].address);
    });

    it('should set bonus on Minter when Timelock is passed ETA', async() => {
      let eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'setBonus(uint256,uint256,uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'uint256', 'uint256'],
          [2, 888888, BONUS_LOCK_RATIO]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await timelockAsDev.executeTransaction(
        shield.address, '0', 'setBonus(uint256,uint256,uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256', 'uint256', 'uint256'],
          [2, 888888, BONUS_LOCK_RATIO]), eta
      );

      expect(await minter.bonusMultiplier()).to.be.bignumber.eq(2);
      expect(await minter.bonusEndBlock()).to.be.bignumber.eq(888888);
      expect(await minter.bonusLockRatio()).to.be.bignumber.eq(BONUS_LOCK_RATIO);
    });

    it('should set BDL per block on Minter when Timelock is passed ETA', async() => {
      let eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'setRewardsPerBlock(uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256'],
          [88]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await timelockAsDev.executeTransaction(
        shield.address, '0', 'setRewardsPerBlock(uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['uint256'],
          [88]), eta
      );

      expect(await minter.blockRewards()).to.be.bignumber.eq(88);
    });

    it('should allow to mint Bundle if mintCount <= 8m', async() => {
      let eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'mintWarchest(address,uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['address','uint256'],
          [await alice.getAddress(), ethers.utils.parseEther('250000')]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await timelockAsDev.executeTransaction(
        shield.address, '0', 'mintWarchest(address,uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['address','uint256'],
          [await alice.getAddress(), ethers.utils.parseEther('250000')]), eta
      );

      expect(await shield.mintCount()).to.be.bignumber.eq(ethers.utils.parseEther('500000'));
      expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.eq(ethers.utils.parseEther('250000'));

      for(let i = 0; i < 20; i++) {
        eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
        await timelockAsDev.queueTransaction(
          shield.address, '0', 'mintWarchest(address,uint256)',
          ethers.utils.defaultAbiCoder.encode(
            ['address','uint256'],
            [await alice.getAddress(), ethers.utils.parseEther('500000')]), eta
        );
  
        await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
  
        await timelockAsDev.executeTransaction(
          shield.address, '0', 'mintWarchest(address,uint256)',
          ethers.utils.defaultAbiCoder.encode(
            ['address','uint256'],
            [await alice.getAddress(), ethers.utils.parseEther('500000')]), eta
        );
      }

      expect(await shield.mintCount()).to.be.bignumber.eq(ethers.utils.parseEther('10500000'));
      expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.eq(ethers.utils.parseEther('10250000'));
    });

    it('should revert when mintCount > 10.5m', async() => {
      let eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'mintWarchest(address,uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['address','uint256'],
          [await alice.getAddress(), ethers.utils.parseEther('250000')]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await timelockAsDev.executeTransaction(
        shield.address, '0', 'mintWarchest(address,uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['address','uint256'],
          [await alice.getAddress(), ethers.utils.parseEther('250000')]), eta
      );

      expect(await shield.mintCount()).to.be.bignumber.eq(ethers.utils.parseEther('500000'));
      expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.eq(ethers.utils.parseEther('250000'));

      for(let i = 0; i < 20; i++) {
        eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
        await timelockAsDev.queueTransaction(
          shield.address, '0', 'mintWarchest(address,uint256)',
          ethers.utils.defaultAbiCoder.encode(
            ['address','uint256'],
            [await alice.getAddress(), ethers.utils.parseEther('500000')]), eta
        );
  
        await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
  
        await timelockAsDev.executeTransaction(
          shield.address, '0', 'mintWarchest(address,uint256)',
          ethers.utils.defaultAbiCoder.encode(
            ['address','uint256'],
            [await alice.getAddress(), ethers.utils.parseEther('500000')]), eta
        );
      }

      eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
      await timelockAsDev.queueTransaction(
        shield.address, '0', 'mintWarchest(address,uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['address','uint256'],
          [await alice.getAddress(), ethers.utils.parseEther('1')]), eta
      );

      await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));

      await expect(timelockAsDev.executeTransaction(
        shield.address, '0', 'mintWarchest(address,uint256)',
        ethers.utils.defaultAbiCoder.encode(
          ['address','uint256'],
          [await alice.getAddress(), ethers.utils.parseEther('1')]), eta
      )).to.be.revertedWith('Shield::mintWarchest:: mint exceeded mintLimit');
      expect(await shield.mintCount()).to.be.bignumber.eq(ethers.utils.parseEther('10500000'));
      expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.eq(ethers.utils.parseEther('10250000'));
    });

    it('should revert when amount > 500000', async() => {
        let eta = (await TimeHelpers.latest()).add(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
        await timelockAsDev.queueTransaction(
          shield.address, '0', 'mintWarchest(address,uint256)',
          ethers.utils.defaultAbiCoder.encode(
            ['address','uint256'],
            [await alice.getAddress(), ethers.utils.parseEther('500001')]), eta
        );
  
        await TimeHelpers.increase(TimeHelpers.duration.days(ethers.BigNumber.from('4')));
  
        await expect(timelockAsDev.executeTransaction(
          shield.address, '0', 'mintWarchest(address,uint256)',
          ethers.utils.defaultAbiCoder.encode(
            ['address','uint256'],
            [await alice.getAddress(), ethers.utils.parseEther('500001')]), eta
        )).to.be.revertedWith('Shield::mintWarchest:: mint exceeded individualMintLimit');
    });
  });
});
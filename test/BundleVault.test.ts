import { ethers, upgrades } from 'hardhat';
import { BigNumber, Signer } from 'ethers';
import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import '@openzeppelin/test-helpers';
import {
    Bundle,
    BundleFactory,
    BundleFactory__factory,
    BundleToken,
    BundleToken__factory,
    BundleVault,
    BundleVault__factory,
    Bundle__factory,
    Controller,
    MockERC20,
    MockERC20__factory,
    MockWBNB,
    MockWBNB__factory,
    PancakeFactory,
    PancakeFactory__factory,
    PancakeRouter,
    PancakeRouter__factory,
    Rebalancer,
    Unbinder,
    Unbinder__factory,
    UpgradeableBeacon,
    UpgradeableBeacon__factory,
} from '../typechain';
import { duration, increase } from './helpers/time';

chai.use(solidity);
const { expect } = chai;

describe('BundleToken', () => {
    // Accounts
    let deployer: Signer;
    let alice: Signer;
    let bob: Signer;

    let bundleToken: BundleToken;
    let bundleTokenAsAlice: BundleToken;
    let bundleTokenAsBob: BundleToken;
    let bundleVault: BundleVault;
    let bundleVaultAsAlice: BundleVault;
    let bundleVaultAsBob: BundleVault;

    // Contract as Signer
    let token0: MockERC20;
    let token1: MockERC20;
    let peg: MockERC20;

    let bundle: Bundle;
    let bundleBeacon: UpgradeableBeacon;
    let unbinder: Unbinder;
    let unbinderBeacon: UpgradeableBeacon;
    let bundleFactory: BundleFactory;
    let controller: Controller;
    let tokens: MockERC20[];
    let rebalancer: Rebalancer;
    let factory: PancakeFactory;
    let wbnb: MockWBNB;
    let router: PancakeRouter;

    let bundleAddr: string;

    beforeEach(async () => {
        [deployer, alice, bob] = await ethers.getSigners();

        // Setup Minter contract
        // Deploy BDL
        const BundleToken = (await ethers.getContractFactory('BundleToken', deployer)) as BundleToken__factory;
        bundleToken = await BundleToken.deploy(132, 137);
        await bundleToken.deployed();
        bundleTokenAsAlice = BundleToken__factory.connect(bundleToken.address, alice);
        bundleTokenAsBob = BundleToken__factory.connect(bundleToken.address, bob);

        // Setup Pancakeswap
        const PancakeFactory = (await ethers.getContractFactory('PancakeFactory', deployer)) as PancakeFactory__factory;
        factory = await PancakeFactory.deploy(await deployer.getAddress());
        await factory.deployed();

        const WBNB = (await ethers.getContractFactory('MockWBNB', deployer)) as MockWBNB__factory;
        wbnb = await WBNB.deploy();
        await wbnb.deployed();

        const PancakeRouter = (await ethers.getContractFactory('PancakeRouter', deployer)) as PancakeRouter__factory;
        router = await PancakeRouter.deploy(factory.address, wbnb.address);
        await router.deployed();

        const UpgradeableBeacon = (await ethers.getContractFactory(
            'UpgradeableBeacon',
            deployer
        )) as UpgradeableBeacon__factory;

        // Deploy bundle and beacon
        const Bundle = (await ethers.getContractFactory('Bundle')) as Bundle__factory;
        bundle = await Bundle.deploy();
        await bundle.deployed();
        bundleBeacon = await UpgradeableBeacon.deploy(bundle.address);
        await bundleBeacon.deployed();

        // Deploy unbinder and beacon
        const Unbinder = (await ethers.getContractFactory('Unbinder')) as Unbinder__factory;
        unbinder = await Unbinder.deploy();
        await unbinder.deployed();
        unbinderBeacon = await UpgradeableBeacon.deploy(unbinder.address);
        await unbinderBeacon.deployed();

        // Deploy factory
        const BundleFactory: BundleFactory__factory = await ethers.getContractFactory('BundleFactory', deployer);
        bundleFactory = await BundleFactory.deploy(unbinderBeacon.address, bundleBeacon.address);
        await bundleFactory.deployed();

        // Deploy controller
        const Controller = await ethers.getContractFactory('Controller');
        controller = (await upgrades.deployProxy(Controller, [
            bundleFactory.address,
            ethers.constants.AddressZero,
        ])) as Controller;
        await controller.deployed();

        // Deploy rebalancer
        const Rebalancer = await ethers.getContractFactory('Rebalancer');
        rebalancer = (await upgrades.deployProxy(Rebalancer, [router.address, controller.address])) as Rebalancer;
        await rebalancer.deployed();

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(controller.address);

        // Set rebalancer on controller as deployer for testing
        await controller.setRebalancer(await rebalancer.address);
        await controller.setDelay(duration.days(ethers.BigNumber.from('1')));

        tokens = new Array();
        for (let i = 0; i < 3; i++) {
            const MockERC20 = (await ethers.getContractFactory('MockERC20', deployer)) as MockERC20__factory;
            const mockERC20 = (await upgrades.deployProxy(MockERC20, [`TOKEN${i}`, `TOKEN${i}`])) as MockERC20;
            await mockERC20.deployed();
            tokens.push(mockERC20);
        }

        token0 = MockERC20__factory.connect(tokens[0].address, deployer);
        token1 = MockERC20__factory.connect(tokens[1].address, deployer);
        peg = MockERC20__factory.connect(tokens[2].address, deployer);

        // Mint tokens
        await token0.mint(await deployer.getAddress(), ethers.utils.parseEther('2000000'));
        await token1.mint(await deployer.getAddress(), ethers.utils.parseEther('1000000'));
        await peg.mint(await deployer.getAddress(), ethers.utils.parseEther('4000000'));
        await bundleToken.mint(await deployer.getAddress(), ethers.utils.parseEther('10000000'));
        await bundleToken.mint(await alice.getAddress(), ethers.utils.parseEther('10000'));
        await bundleToken.mint(await bob.getAddress(), ethers.utils.parseEther('10000'));

        // Deploy bundle
        await (await controller.deploy('Test', 'TST')).wait();
        bundleAddr = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.bundle;
        bundle = Bundle__factory.connect(bundleAddr, deployer);

        // Approve transfers for bundle and router
        await token0.approve(bundle.address, ethers.constants.MaxUint256);
        await token1.approve(bundle.address, ethers.constants.MaxUint256);

        await token0.approve(router.address, ethers.constants.MaxUint256);
        await token1.approve(router.address, ethers.constants.MaxUint256);
        await peg.approve(router.address, ethers.constants.MaxUint256);
        await bundleToken.approve(router.address, ethers.constants.MaxUint256);

        // Setup bundle
        await controller.setup(
            bundle.address,
            [token0.address, token1.address],
            [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000')],
            [ethers.utils.parseEther('2'), ethers.utils.parseEther('2')],
            await deployer.getAddress()
        );

        // Add liquidity for tokens
        await router.addLiquidity(
            token0.address,
            peg.address,
            ethers.utils.parseEther('50000'),
            ethers.utils.parseEther('50000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            token1.address,
            peg.address,
            ethers.utils.parseEther('25000'),
            ethers.utils.parseEther('50000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            bundleToken.address,
            peg.address,
            ethers.utils.parseEther('1000000'),
            ethers.utils.parseEther('100000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        const BundleVault = (await ethers.getContractFactory('BundleVault', deployer)) as BundleVault__factory;
        bundleVault = await BundleVault.deploy(
            controller.address,
            bundleToken.address,
            await deployer.getAddress(),
            router.address
        );
        await bundleVault.deployed();
        bundleVaultAsAlice = BundleVault__factory.connect(bundleVault.address, alice);
        bundleVaultAsBob = BundleVault__factory.connect(bundleVault.address, bob);

        await bundleToken.approve(bundleVault.address, ethers.constants.MaxUint256);
        await bundleTokenAsAlice.approve(bundleVault.address, ethers.constants.MaxUint256);
        await bundleTokenAsBob.approve(bundleVault.address, ethers.constants.MaxUint256);

        await bundleVault.setSwapWhitelist([token0.address, token1.address, peg.address], true);

        await controller.setVault(bundleVault.address);
    });

    context('setters', async () => {
        it('sets the swap whitelist', async () => {
            // Succeeds under expected conditions
            await bundleVault.setSwapWhitelist([token0.address], false);
            expect(await bundleVault.isSwapWhitelisted(token0.address)).to.eq(false);
            expect((await bundleVault.getSwapTokens())[0]).to.eq(peg.address);
            expect((await bundleVault.getSwapTokens())[1]).to.eq(token1.address);

            // Reverts when not owner
            await expect(bundleVaultAsAlice.setSwapWhitelist([token0.address], true)).to.be.reverted;

            // Reverts when state not changed
            await expect(bundleVault.setSwapWhitelist([token0.address], false)).to.be.reverted;
        });

        it('sets the dev fee', async () => {
            await bundleVault.setDevShare(1000);
            expect(await bundleVault.getDevShare()).to.be.bignumber.and.eq(1000);

            await expect(bundleVaultAsAlice.setDevShare(1000)).to.be.reverted;
        });

        it('sets the caller fee', async () => {
            await bundleVault.setCallerShare(1000);
            expect(await bundleVault.getCallerShare()).to.be.bignumber.and.eq(1000);

            await expect(bundleVaultAsAlice.setCallerShare(1000)).to.be.reverted;
        });

        it('sets the dev', async () => {
            await bundleVault.setDev(await alice.getAddress());
            expect(await bundleVault.getDev()).to.eq(await alice.getAddress());

            await expect(bundleVault.setDev(await alice.getAddress())).to.be.reverted;

            await bundleVaultAsAlice.setDev(await deployer.getAddress());
            expect(await bundleVault.getDev()).to.eq(await deployer.getAddress());
        });
    });

    context('deposit', async () => {
        it('deposits successfully', async () => {
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));
            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq('0');
            expect(await bundleToken.balanceOf(bundleVault.address)).to.bignumber.and.eq(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('7')));

            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq('0');
            expect(await bundleToken.balanceOf(bundleVault.address)).to.bignumber.and.eq(ethers.utils.parseEther('100'));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('10'));

            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('110'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.bignumber.and.eq(ethers.utils.parseEther('110'));

            await bundleToken.transfer(bundleVault.address, ethers.utils.parseEther('100'));
            await increase(duration.days(BigNumber.from('7')));

            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('210'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.bignumber.and.eq(ethers.utils.parseEther('210'));

            await bundleVaultAsBob.deposit(ethers.utils.parseEther('10'));

            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('210'));
            expect(await bundleVault.getBalance(await bob.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('10'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq(ethers.utils.parseEther('105'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.bignumber.and.eq(ethers.utils.parseEther('220'));
        });

        it('deposits successfully with bundle already send', async () => {
            await bundleToken.transfer(bundleVault.address, ethers.utils.parseEther('100'));
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));
            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq('0');
            expect(await bundleToken.balanceOf(bundleVault.address)).to.bignumber.and.eq(ethers.utils.parseEther('200'));

            await increase(duration.days(BigNumber.from('7')));

            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq('0');
            expect(await bundleToken.balanceOf(bundleVault.address)).to.bignumber.and.eq(ethers.utils.parseEther('200'));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('10'));

            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('210'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.bignumber.and.eq(ethers.utils.parseEther('210'));
        });
    });

    context('withdraw', async () => {
        it('fails when withdrawing too much and no deposits', async () => {
            await expect(bundleVaultAsAlice.withdraw(ethers.utils.parseEther('100'))).to.be.revertedWith('ERR_AMOUNT_TOO_LARGE');
        });

        it('fails when withdrawing too much from just deposits', async () => {
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));
            await expect(bundleVaultAsAlice.withdraw(ethers.utils.parseEther('100').add('100000'))).to.be.revertedWith('ERR_AMOUNT_TOO_LARGE');
        });

        it('fails when withdrawing too much from active', async () => {
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));
            await bundleToken.transfer(bundleVault.address, ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('7')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('10'));
            await expect(bundleVaultAsAlice.withdraw(ethers.utils.parseEther('210').add('100000'))).to.be.revertedWith('ERR_AMOUNT_TOO_LARGE');
        });

        it('fails when withdrawing too much and multiple users', async () => {
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));
            await bundleToken.transfer(bundleVault.address, ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('7')));

            await bundleVaultAsBob.deposit(ethers.utils.parseEther('10'));

            await increase(duration.days(BigNumber.from('7')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('10'));

            await expect(bundleVaultAsAlice.withdraw(ethers.utils.parseEther('210').add('100000'))).to.be.revertedWith('ERR_AMOUNT_TOO_LARGE');
            await expect(bundleVaultAsBob.withdraw(ethers.utils.parseEther('10').add('100000'))).to.be.revertedWith('ERR_AMOUNT_TOO_LARGE');
        });

        it('succeeds for multiple same-day deposits', async () => {
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));
            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('200'));

            await increase(duration.days(BigNumber.from('7')));

            await bundleVaultAsAlice.withdraw(ethers.utils.parseEther('200'));
            expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('10000'));
            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq('0');
            expect(await bundleToken.balanceOf(bundleVault.address)).to.be.bignumber.and.eq('0');
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq('0');
        });

        it('succeeds with correct amounts', async () => {
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));
            await bundleToken.transfer(bundleVault.address, ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('7')));

            await bundleVaultAsBob.deposit(ethers.utils.parseEther('10'));

            await increase(duration.days(BigNumber.from('7')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('10'));

            await bundleVaultAsAlice.withdraw(ethers.utils.parseEther('205'));
            expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('10095'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.be.bignumber.and.eq(ethers.utils.parseEther('15'));
            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('5'));

            await increase(duration.days(BigNumber.from('7')));

            await bundleVaultAsAlice.withdraw(ethers.utils.parseEther('5'));
            expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('10100'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.be.bignumber.and.eq(ethers.utils.parseEther('10'));
            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('0'));

            await bundleVaultAsBob.withdraw(ethers.utils.parseEther('10'));
            expect(await bundleToken.balanceOf(await bob.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('10000'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.be.bignumber.and.eq(ethers.utils.parseEther('0'));
            expect(await bundleVault.getBalance(await bob.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('0'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq('0');

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('10'));

            await increase(duration.days(BigNumber.from('7')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('10'));
            await bundleVaultAsAlice.withdraw(ethers.utils.parseEther('20'));
            expect(await bundleToken.balanceOf(await bob.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('10000'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.be.bignumber.and.eq(ethers.utils.parseEther('0'));
            expect(await bundleVault.getBalance(await bob.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('0'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq('0');
        });

        it('succeeds with maxed out deposits array', async () => {
            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('1')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('1')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('1')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('1')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('1')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('1')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('1')));

            await bundleVaultAsAlice.deposit(ethers.utils.parseEther('100'));

            await bundleVaultAsAlice.withdraw(ethers.utils.parseEther('400'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.be.bignumber.and.eq(ethers.utils.parseEther('400'));
            expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('9600'));
            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('400'));
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));

            await increase(duration.days(BigNumber.from('1')));

            await bundleVaultAsAlice.withdraw(ethers.utils.parseEther('400'));
            expect(await bundleToken.balanceOf(bundleVault.address)).to.be.bignumber.and.eq('0');
            expect(await bundleToken.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('10000'));
            expect(await bundleVault.getBalance(await alice.getAddress())).to.be.bignumber.and.eq('0');
            expect(await bundleVault.getCumulativeBalance()).to.be.bignumber.and.eq('0');
        });
    });
});

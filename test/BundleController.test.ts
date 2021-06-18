import { ethers, upgrades } from "hardhat";
import { Signer } from "ethers";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import "@openzeppelin/test-helpers";
import {
    Bundle,
    Bundle__factory,
    BundleFactory,
    BundleFactory__factory,
    Controller,
    Controller__factory,
    MockERC20,
    MockERC20__factory,
    UpgradeableBeacon,
    UpgradeableBeacon__factory,
    Unbinder,
    Unbinder__factory,
    Rebalancer
} from "../typechain";
import { advanceBlockTo } from "./helpers/time";

chai.use(solidity);
const { expect } = chai;

describe("Controller", () => {
    // Contract as Signer
    let controllerAsDeployer: Controller;
    let controllerAsAlice: Controller;
    let token0AsDeployer: MockERC20;
    let token1AsDeployer: MockERC20;

    // Accounts
    let deployer: Signer;
    let alice: Signer;

    let bundle: Bundle;
    let bundleBeacon: UpgradeableBeacon;
    let unbinder: Unbinder;
    let unbinderBeacon: UpgradeableBeacon;
    let bundleFactory: BundleFactory;
    let controller: Controller;
    let rebalancer: Rebalancer;
    let tokens: MockERC20[];

    beforeEach(async() => {
        [deployer, alice] = await ethers.getSigners();

        const UpgradeableBeacon = await ethers.getContractFactory(
            "UpgradeableBeacon", deployer) as UpgradeableBeacon__factory;

        // Deploy bundle and beacon
        const Bundle = await ethers.getContractFactory("Bundle") as Bundle__factory;
        bundle = await Bundle.deploy();
        await bundle.deployed();
        bundleBeacon = await UpgradeableBeacon.deploy(bundle.address);
        await bundleBeacon.deployed();

        // Deploy unbinder and beacon
        const Unbinder = await ethers.getContractFactory("Unbinder") as Unbinder__factory;
        unbinder = await Unbinder.deploy();
        await unbinder.deployed();
        unbinderBeacon = await UpgradeableBeacon.deploy(unbinder.address);
        await unbinderBeacon.deployed();

        // Deploy factory
        const BundleFactory: BundleFactory__factory = await ethers.getContractFactory(
            "BundleFactory", deployer);
        bundleFactory = await BundleFactory.deploy(unbinderBeacon.address, bundleBeacon.address);
        await bundleFactory.deployed();

        // Deploy controller
        const Controller = await ethers.getContractFactory("Controller");
        controller = await upgrades.deployProxy(
            Controller, 
            [bundleFactory.address, ethers.constants.AddressZero]
        ) as Controller;
        await controller.deployed();

        // Deploy controller
        const Rebalancer = await ethers.getContractFactory("Rebalancer");
        rebalancer = await upgrades.deployProxy(
            Rebalancer, 
            [ethers.constants.AddressZero, controller.address, ethers.constants.AddressZero, await deployer.getAddress()]
        ) as Rebalancer;
        await controller.deployed();

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(controller.address);

        // Set rebalancer on controller
        await controller.setRebalancer(rebalancer.address);

        controllerAsDeployer = Controller__factory.connect(controller.address, deployer);
        controllerAsAlice = Controller__factory.connect(controller.address, alice);

        tokens = new Array();
        for(let i = 0; i < 4; i++) {
            const MockERC20 = (await ethers.getContractFactory(
                "MockERC20",
                deployer
            )) as MockERC20__factory;
            const mockERC20 = await upgrades.deployProxy(MockERC20, [`TOKEN${i}`, `TOKEN${i}`]) as MockERC20;
            await mockERC20.deployed();
            tokens.push(mockERC20);
        }

        token0AsDeployer = MockERC20__factory.connect(tokens[0].address, deployer);
        token1AsDeployer = MockERC20__factory.connect(tokens[1].address, deployer);
    });

    context('rebalancer', async () => {
        it('sets premium', async () => {
            await controllerAsDeployer.setPremium(ethers.utils.parseEther('1').div(10));
            expect(await rebalancer.getPremium()).to.be.bignumber.and.eq(ethers.utils.parseEther('1').div(10));
        });

        it('whitelists a bundle', async () => {
            await controllerAsDeployer.setWhitelist(await deployer.getAddress(), true);
            expect(await rebalancer.isWhitelisted(await deployer.getAddress())).to.eq(true);
        });

        it('sets the lock', async () => {
            expect(await rebalancer.isLocked()).to.eq(true);
            await controllerAsDeployer.setLock(false);
            expect(await rebalancer.isLocked()).to.eq(false);
        });
    });

    context('unbinder', async () => {
        it('sets variables', async () => {
            await (await controllerAsDeployer.deploy("Test", "TST")).wait();
            const unbinder = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.unbinder;
            const newUnbinder = Unbinder__factory.connect(unbinder, deployer);

            // Set premium
            await controllerAsDeployer.setUnbinderPremium([newUnbinder.address], ethers.utils.parseEther('1').mul(5).div(100));
            expect(await newUnbinder.getPremium()).to.be.bignumber.and.eq(ethers.utils.parseEther('1').mul(5).div(100));

            // Whitelist route token
            await controllerAsDeployer.setRouteToken([newUnbinder.address], ethers.constants.AddressZero, true);
            expect(await newUnbinder.isWhitelisted(ethers.constants.AddressZero)).to.eq(true);
        });
    });

    context('controller', async () => {
        it('sets delay', async () => {
            await controllerAsDeployer.setDelay(28800);
            expect(await controller.getDelay()).to.be.bignumber.and.eq(28800);
        });

        it('reverts if below min delay', async () => {
            await expect(controllerAsDeployer.setDelay(28799)).to.be.reverted;
        });

        it('deploys and initializes a bundle', async () => {
            // Mint tokens
            await token0AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('10000'));
            await token1AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('5000'));

            // Deploy bundle
            await (await controllerAsDeployer.deploy("Test", "TST")).wait();
            const bundle = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.bundle;
            const newBundle = Bundle__factory.connect(bundle, deployer);

            // Approve transfers for bundle
            await token0AsDeployer.approve(newBundle.address, ethers.constants.MaxUint256);
            await token1AsDeployer.approve(newBundle.address, ethers.constants.MaxUint256);

            await controllerAsDeployer.setup(
                newBundle.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000')],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1')],
                await deployer.getAddress()
            );

            expect(await newBundle.isPublicSwap()).to.eq(true);

            // Sets swap fee
            await controllerAsDeployer.setSwapFee(newBundle.address, ethers.utils.parseEther('1').div(10));
            expect(await newBundle.getSwapFee()).to.be.bignumber.and.eq(ethers.utils.parseEther('1').div(10));

            // Sets rebalancable
            await controllerAsDeployer.setRebalancable(newBundle.address, true);
            expect(await newBundle.getRebalancable()).to.eq(true);

            // Sets public swap
            await controllerAsDeployer.setPublicSwap(newBundle.address, true);
            expect(await newBundle.isPublicSwap()).to.eq(true);

            // Sets min balance for token
            await expect(controllerAsDeployer.setMinBalance(newBundle.address, token0AsDeployer.address, 0)).to.be.revertedWith("ERR_READY");

            // Sets streaming fee
            await controllerAsDeployer.setStreamingFee(newBundle.address, ethers.utils.parseEther('1').div(100));
            expect(await newBundle.getStreamingFee()).to.be.bignumber.and.eq(ethers.utils.parseEther('1').div(100));

            // Sets exit fee
            await controllerAsDeployer.setExitFee(newBundle.address, ethers.utils.parseEther('1').div(100));
            expect(await newBundle.getExitFee()).to.be.bignumber.and.eq(ethers.utils.parseEther('1').div(100));

            // Collects streaming fee
            await controllerAsDeployer.collectStreamingFee(newBundle.address);
            expect(await token0AsDeployer.balanceOf(controller.address)).to.be.bignumber.and.eq('57077625570776');
            expect(await token1AsDeployer.balanceOf(controller.address)).to.be.bignumber.and.eq('28538812785388');

            // Transfer to owner
            await expect(
                controllerAsAlice.collectTokens(
                [token0AsDeployer.address, token1AsDeployer.address],
                ['57077625570776', '28538812785388'],
                await deployer.getAddress()
            )).to.be.reverted;

            await controllerAsDeployer.collectTokens(
                [token0AsDeployer.address, token1AsDeployer.address],
                ['57077625570776', '28538812785388'],
                await deployer.getAddress()
            );
            expect(await token0AsDeployer.balanceOf(await deployer.getAddress())).to.be.bignumber.and.eq('57077625570776');
            expect(await token1AsDeployer.balanceOf(await deployer.getAddress())).to.be.bignumber.and.eq('28538812785388');

            // Fails to set swap fee as non-owner
            await expect(controllerAsAlice.setSwapFee(newBundle.address, ethers.utils.parseEther('1').div(10))).to.be.reverted;

            // Fails to set swap fee as non-owner
            await expect(controllerAsAlice.setRebalancable(newBundle.address, true)).to.be.reverted;

            // Fails to set swap fee as non-owner
            await expect(controllerAsAlice.setPublicSwap(newBundle.address, true)).to.be.reverted;

            // Fails to set swap fee as non-owner
            await expect(controllerAsAlice.setMinBalance(newBundle.address, token0AsDeployer.address, 0)).to.be.reverted;

            // Fails to set swap fee as non-owner
            await expect(controllerAsAlice.setStreamingFee(newBundle.address, ethers.utils.parseEther('1').div(100))).to.be.reverted;

            // Fails to set swap fee as non-owner
            await expect(controllerAsAlice.setExitFee(newBundle.address, ethers.utils.parseEther('1').div(100))).to.be.reverted;

            await controllerAsDeployer.setDelay(28800);

            await expect(controllerAsDeployer.reweighTokens(
                newBundle.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('1'), ethers.utils.parseEther('1')]
            )).to.be.revertedWith("ERR_DELAY");
            await advanceBlockTo((await ethers.provider.getBlockNumber()) + 28800);
            await controllerAsDeployer.reweighTokens(
                newBundle.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('1'), ethers.utils.parseEther('1')]
            );

            await expect(controllerAsDeployer.reindexTokens(
                newBundle.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('1'), ethers.utils.parseEther('1')],
                [0, 0]
            )).to.be.revertedWith("ERR_DELAY");
            await advanceBlockTo((await ethers.provider.getBlockNumber()) + 28800);
            await controllerAsDeployer.reindexTokens(
                newBundle.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('1'), ethers.utils.parseEther('1')],
                [0, 0]
            );

            expect((await controller.getBundleMetadata(newBundle.address))[3]).to.be.bignumber.and.eq(await ethers.provider.getBlockNumber());
        }).timeout(100000);
    });
});

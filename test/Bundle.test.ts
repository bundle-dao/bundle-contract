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

chai.use(solidity);
const { expect } = chai;

describe("Bundle", () => {
    // Contract as Signer
    let controllerAsDeployer: Controller;
    let controllerAsAlice: Controller;
    let token0AsDeployer: MockERC20;
    let token1AsDeployer: MockERC20;
    let token0AsAlice: MockERC20;
    let token1AsAlice: MockERC20;
    let bundleAsDeployer: Bundle;
    let bundleAsAlice: Bundle;

    // Accounts
    let deployer: Signer;
    let alice: Signer;

    let bundle: Bundle;
    let bundleBeacon: UpgradeableBeacon;
    let unbinder: Unbinder;
    let unbinderBeacon: UpgradeableBeacon;
    let bundleFactory: BundleFactory;
    let controller: Controller;
    let tokens: MockERC20[];
    let rebalancer: Rebalancer;

    const errorDelta = 10 ** 8;

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

        // Deploy rebalancer
        const Rebalancer = await ethers.getContractFactory("Rebalancer");
        rebalancer = await upgrades.deployProxy(
            Rebalancer, 
            [ethers.constants.AddressZero, controller.address, ethers.constants.AddressZero, await deployer.getAddress()]
        ) as Rebalancer;
        await rebalancer.deployed();

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(controller.address);

        // Set rebalancer on controller as deployer for testing
        await controller.setRebalancer(await rebalancer.address);

        controllerAsDeployer = Controller__factory.connect(controller.address, deployer);
        controllerAsAlice = Controller__factory.connect(controller.address, alice);

        tokens = new Array();
        for(let i = 0; i < 2; i++) {
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
        token0AsAlice = MockERC20__factory.connect(tokens[0].address, alice);
        token1AsAlice = MockERC20__factory.connect(tokens[1].address, alice);

        // Mint tokens
        await token0AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('10000'));
        await token1AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('5000'));

        // Deploy bundle
        await (await controllerAsDeployer.deploy("Test", "TST")).wait();
        let bundleAddr = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.bundle;
        bundleAsDeployer = Bundle__factory.connect(bundleAddr, deployer);
        bundleAsAlice = Bundle__factory.connect(bundleAddr, alice);
    });

    context('user interaction', async () => {
        it('joins and leaves the pool', async () => {
            // Approve transfers for bundle
            await token0AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await controllerAsDeployer.setup(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000')],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1')],
                await deployer.getAddress()
            );

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await bundleAsAlice.joinPool(ethers.utils.parseEther('10'), [ethers.utils.parseEther('1000'), ethers.utils.parseEther('500')]);
            expect(await token0AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(0);
            expect(await token1AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(0);
            expect(await bundleAsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('10'));

            // Expect a 2% fee to be applied
            await bundleAsAlice.exitPool(ethers.utils.parseEther('10'), [ethers.utils.parseEther('980'), ethers.utils.parseEther('490')]);
            // Account for negligible rounding error, see balancer trail of bits audit for explanation
            expect(await token0AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('980').add(1000));
            expect(await token1AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('490').add(500));
            expect(await bundleAsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(0);
            expect(await bundleAsAlice.balanceOf(controller.address)).to.be.bignumber.and.eq(ethers.utils.parseEther('2').div(10));
            expect(await bundleAsAlice.balanceOf(await deployer.getAddress())).to.be.bignumber.and.eq(ethers.utils.parseEther('100'));
        });

        it('reverts if pool not initialized', async () => {
            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await expect(
                bundleAsAlice.joinPool(ethers.utils.parseEther('10'), [ethers.utils.parseEther('1000'), ethers.utils.parseEther('500')])
            ).to.be.reverted;
        });
    });
});

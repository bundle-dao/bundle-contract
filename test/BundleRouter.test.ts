import { ethers, upgrades } from 'hardhat';
import { Signer } from 'ethers';
import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import '@openzeppelin/test-helpers';
import {
    Bundle,
    Bundle__factory,
    BundleFactory,
    BundleFactory__factory,
    Controller,
    MockERC20,
    MockERC20__factory,
    MockWBNB,
    MockWBNB__factory,
    PancakeRouter,
    PancakeRouter__factory,
    PancakeFactory,
    PancakeFactory__factory,
    UpgradeableBeacon,
    UpgradeableBeacon__factory,
    Unbinder,
    Unbinder__factory,
    BundleRouter,
    BundleRouter__factory,
    Rebalancer
} from '../typechain';
import { duration } from './helpers/time';

chai.use(solidity);
const { expect } = chai;

describe('BundleRouter', () => {
    // Contract as Signer
    let controllerAsDeployer: Controller;
    let token0AsDeployer: MockERC20;
    let token1AsDeployer: MockERC20;
    let token2AsDeployer: MockERC20;
    let bundleAsDeployer: Bundle;
    let bundleAsAlice: Bundle;
    let unbinderAsAlice: Unbinder;
    let bundleRouterAsAlice: BundleRouter;

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
    let factory: PancakeFactory;
    let wbnb: MockWBNB;
    let router: PancakeRouter;
    let bundleRouter: BundleRouter;
    let rebalancer: Rebalancer;

    let bundleAddr: string;
    let unbinderAddr: string;

    beforeEach(async () => {
        [deployer, alice] = await ethers.getSigners();

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

        tokens = new Array();
        for (let i = 0; i < 3; i++) {
            const MockERC20 = (await ethers.getContractFactory('MockERC20', deployer)) as MockERC20__factory;
            const mockERC20 = (await upgrades.deployProxy(MockERC20, [`TOKEN${i}`, `TOKEN${i}`])) as MockERC20;
            await mockERC20.deployed();
            tokens.push(mockERC20);
        }

        token0AsDeployer = MockERC20__factory.connect(tokens[0].address, deployer);
        token1AsDeployer = MockERC20__factory.connect(tokens[1].address, deployer);
        token2AsDeployer = MockERC20__factory.connect(tokens[2].address, deployer);

        // Mint tokens
        await token0AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('1000000'));
        await token1AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('1000000'));
        await token2AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('1000000'));

        // Deploy controller
        const Controller = await ethers.getContractFactory('Controller');
        controller = (await upgrades.deployProxy(Controller, [bundleFactory.address, router.address])) as Controller;
        await controller.deployed();

        // Deploy rebalancer
        const Rebalancer = await ethers.getContractFactory('Rebalancer');
        rebalancer = (await upgrades.deployProxy(Rebalancer, [router.address, controller.address])) as Rebalancer;
        await rebalancer.deployed();

        // Set rebalancer on controller as deployer for testing
        await controller.setRebalancer(await rebalancer.address);

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(controller.address);

        await controller.setDelay(duration.days(ethers.BigNumber.from('1')));

        // Deploy bundle
        await (await controller.deploy('Test', 'TST')).wait();
        bundleAddr = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.bundle;
        unbinderAddr = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.unbinder;
        bundleAsDeployer = Bundle__factory.connect(bundleAddr, deployer);
        bundleAsAlice = Bundle__factory.connect(bundleAddr, alice);
        unbinderAsAlice = Unbinder__factory.connect(unbinderAddr, alice);

        // Approve transfers for bundle and router
        await token0AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
        await token1AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
        await token2AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

        await token0AsDeployer.approve(router.address, ethers.constants.MaxUint256);
        await token1AsDeployer.approve(router.address, ethers.constants.MaxUint256);
        await token2AsDeployer.approve(router.address, ethers.constants.MaxUint256);

        // Setup bundle
        await controller.setup(
            bundleAsDeployer.address,
            [token0AsDeployer.address, token1AsDeployer.address],
            [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000')],
            [ethers.utils.parseEther('9'), ethers.utils.parseEther('3')],
            await deployer.getAddress()
        );

        // Add liquidity for tokens
        await router.addLiquidity(
            token0AsDeployer.address,
            token2AsDeployer.address,
            ethers.utils.parseEther('50000'),
            ethers.utils.parseEther('50000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            token1AsDeployer.address,
            token2AsDeployer.address,
            ethers.utils.parseEther('50000'),
            ethers.utils.parseEther('50000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        const BundleRouter = (await ethers.getContractFactory('BundleRouter', deployer)) as BundleRouter__factory;
        bundleRouter = await BundleRouter.deploy(router.address);
        await bundleRouter.deployed();
        bundleRouterAsAlice = BundleRouter__factory.connect(bundleRouter.address, alice);

        await bundleRouter.setWhitelist(bundleAddr, true);
    });

    context('getters', async () => {
        it('returns the correct whitelist value', async () => {
            expect(await bundleRouterAsAlice.isWhitelisted(bundleAddr)).to.eq(true);
        });

        it('returns the router address', async () => {
            expect(await bundleRouterAsAlice.getRouter()).to.eq(router.address);
        });
    });

    context('setters', async () => {
        it('reverts when non-owner sets whitelist', async () => {
            await expect(bundleRouterAsAlice.setWhitelist(bundleAddr, false)).to.be.reverted;
        });
    });

    context('minting', async () => {});

    context('redeeming', async () => {});
});

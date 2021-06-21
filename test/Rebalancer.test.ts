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
    Controller__factory,
    MockERC20,
    MockERC20__factory,
    MockWBNB,
    MockWBNB__factory,
    PancakeRouter,
    PancakeRouter__factory,
    PancakeFactory,
    PancakeFactory__factory,
    PriceOracle,
    PriceOracle__factory,
    UpgradeableBeacon,
    UpgradeableBeacon__factory,
    Unbinder,
    Unbinder__factory,
    Rebalancer,
    Rebalancer__factory
} from '../typechain';
import { duration, increase } from './helpers/time';

chai.use(solidity);
const { expect } = chai;

describe('Rebalancer', () => {
    // Contract as Signer
    let controllerAsDeployer: Controller;
    let controllerAsAlice: Controller;
    let token0AsDeployer: MockERC20;
    let token1AsDeployer: MockERC20;
    let token2AsDeployer: MockERC20;
    let token3AsDeployer: MockERC20;
    let token0AsAlice: MockERC20;
    let token1AsAlice: MockERC20;
    let token2AsAlice: MockERC20;
    let token3AsAlice: MockERC20;
    let bundleAsDeployer: Bundle;
    let bundleAsAlice: Bundle;
    let rebalancerAsAlice: Rebalancer;
    let routerAsAlice: PancakeRouter;

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
    let factory: PancakeFactory;
    let wbnb: MockWBNB;
    let router: PancakeRouter;
    let priceOracle: PriceOracle;

    let bundleAddr: string;

    beforeEach(async () => {
        [deployer, alice] = await ethers.getSigners();

        // Setup Pancakeswap
        const PancakeFactory = (await ethers.getContractFactory(
            "PancakeFactory",
            deployer
        )) as PancakeFactory__factory;
        factory = await PancakeFactory.deploy(await deployer.getAddress());
        await factory.deployed();

        const WBNB = (await ethers.getContractFactory(
            "MockWBNB",
            deployer
        )) as MockWBNB__factory;
        wbnb = await WBNB.deploy();
        await wbnb.deployed();
      
        const PancakeRouter = (await ethers.getContractFactory(
            "PancakeRouter",
            deployer
        )) as PancakeRouter__factory;
        router = await PancakeRouter.deploy(factory.address, wbnb.address);
        await router.deployed();
        routerAsAlice = PancakeRouter__factory.connect(router.address, alice);

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
        rebalancer = (await upgrades.deployProxy(Rebalancer, [
            router.address,
            controller.address
        ])) as Rebalancer;
        await rebalancer.deployed();
        rebalancerAsAlice = Rebalancer__factory.connect(rebalancer.address, alice);

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(controller.address);

        // Set rebalancer on controller as deployer for testing
        await controller.setRebalancer(await rebalancer.address);

        await controller.setDelay(duration.days(ethers.BigNumber.from('1')));

        controllerAsDeployer = Controller__factory.connect(controller.address, deployer);
        controllerAsAlice = Controller__factory.connect(controller.address, alice);

        tokens = new Array();
        for (let i = 0; i < 4; i++) {
            const MockERC20 = (await ethers.getContractFactory('MockERC20', deployer)) as MockERC20__factory;
            const mockERC20 = (await upgrades.deployProxy(MockERC20, [`TOKEN${i}`, `TOKEN${i}`])) as MockERC20;
            await mockERC20.deployed();
            tokens.push(mockERC20);
        }

        token0AsDeployer = MockERC20__factory.connect(tokens[0].address, deployer);
        token1AsDeployer = MockERC20__factory.connect(tokens[1].address, deployer);
        token2AsDeployer = MockERC20__factory.connect(tokens[2].address, deployer);
        token3AsDeployer = MockERC20__factory.connect(tokens[3].address, deployer);
        token0AsAlice = MockERC20__factory.connect(tokens[0].address, alice);
        token1AsAlice = MockERC20__factory.connect(tokens[1].address, alice);
        token2AsAlice = MockERC20__factory.connect(tokens[2].address, alice);
        token3AsAlice = MockERC20__factory.connect(tokens[3].address, alice);

        // Mint tokens
        await token0AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('100000'));
        await token1AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('50000'));
        await token2AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('200000'));
        await token3AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('100000'));
        await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));
        await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('50000'));
        await token2AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));
        await token3AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));

        // Deploy bundle
        await (await controllerAsDeployer.deploy('Test', 'TST')).wait();
        bundleAddr = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.bundle;
        bundleAsDeployer = Bundle__factory.connect(bundleAddr, deployer);
        bundleAsAlice = Bundle__factory.connect(bundleAddr, alice);

        // Approve transfers for bundle and router
        await token0AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
        await token1AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
        await token2AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

        await token0AsDeployer.approve(router.address, ethers.constants.MaxUint256);
        await token1AsDeployer.approve(router.address, ethers.constants.MaxUint256);
        await token2AsDeployer.approve(router.address, ethers.constants.MaxUint256);
        await token3AsDeployer.approve(router.address, ethers.constants.MaxUint256);
        await token0AsAlice.approve(rebalancer.address, ethers.constants.MaxUint256);
        await token0AsAlice.approve(router.address, ethers.constants.MaxUint256);

        // Setup bundle
        await controllerAsDeployer.setup(
            bundleAsDeployer.address,
            [token0AsDeployer.address, token1AsDeployer.address],
            [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000')],
            [ethers.utils.parseEther('2'), ethers.utils.parseEther('2')],
            await deployer.getAddress()
        );

        // Add liquidity for tokens
        await router.addLiquidity(
            token0AsDeployer.address, token2AsDeployer.address,
            ethers.utils.parseEther('50000'), ethers.utils.parseEther('50000'),
            0, 0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            token1AsDeployer.address, token2AsDeployer.address,
            ethers.utils.parseEther('25000'), ethers.utils.parseEther('50000'),
            0, 0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            token0AsDeployer.address, token3AsDeployer.address,
            ethers.utils.parseEther('10000'), ethers.utils.parseEther('9000'),
            0, 0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            token1AsDeployer.address, token3AsDeployer.address,
            ethers.utils.parseEther('10000'), ethers.utils.parseEther('20000'),
            0, 0,
            await deployer.getAddress(),
            '2000000000'
        );

        // Create oracle
        const PriceOracle = (await ethers.getContractFactory(
            'PriceOracle',
            deployer
        )) as PriceOracle__factory;
        priceOracle = await PriceOracle.deploy(factory.address, token2AsDeployer.address);
        await priceOracle.deployed();

        controllerAsDeployer.setOracle(priceOracle.address);
        controllerAsDeployer.setGap(ethers.utils.parseEther('5').div(100));
    });

    context('oracle', async () => {
        it('reverts when initial token invalid', async () => {
            await expect(priceOracle.setReferencePath(token0AsDeployer.address, [token1AsDeployer.address, token2AsDeployer.address])).to.be.revertedWith('ERR_BAD_REFERENCE_PATH');
        });

        it('reverts when last token not peg', async () => {
            await expect(priceOracle.setReferencePath(token0AsDeployer.address, [token0AsDeployer.address, token1AsDeployer.address])).to.be.revertedWith('ERR_BAD_REFERENCE_PATH');
        });

        it('does nothing when not past timeframe', async () => {
            // Setup oracle
            await priceOracle.setReferencePath(token0AsDeployer.address, [token0AsDeployer.address, token2AsDeployer.address]);
            await priceOracle.setReferencePath(token1AsDeployer.address, [token1AsDeployer.address, token2AsDeployer.address]);
            await priceOracle.updateReference(token0AsDeployer.address);
            expect(await priceOracle.consultReference(token0AsDeployer.address, ethers.utils.parseEther('1'))).to.be.bignumber.and.eq(0);
            expect(await priceOracle.consultReference(token1AsDeployer.address, ethers.utils.parseEther('1'))).to.be.bignumber.and.eq(0);
        })
    })

    context('arbitraging', async () => {
        it('reverts when bundle not whitelisted', async () => {
            await controllerAsDeployer.setWhitelist(bundleAsDeployer.address, false);

            await expect(rebalancerAsAlice.swap(
                bundleAsAlice.address,
                token0AsAlice.address,
                token1AsAlice.address,
                ethers.utils.parseEther('100'),
                '2000000000',
                [token1AsAlice.address, token2AsAlice.address, token0AsAlice.address]
            )).to.be.revertedWith('ERR_POOL_WHITELIST');
        });

        it('reverts with invalid end of path', async () => {
            await expect(rebalancerAsAlice.swap(
                bundleAsAlice.address,
                token0AsAlice.address,
                token1AsAlice.address,
                ethers.utils.parseEther('100'),
                '2000000000',
                [token1AsAlice.address, token2AsAlice.address, token1AsAlice.address]
            )).to.be.revertedWith('ERR_BAD_PATH');
        });

        it('reverts with invalid start of path', async () => {
            await expect(rebalancerAsAlice.swap(
                bundleAsAlice.address,
                token0AsAlice.address,
                token1AsAlice.address,
                ethers.utils.parseEther('100'),
                '2000000000',
                [token0AsAlice.address, token2AsAlice.address, token1AsAlice.address]
            )).to.be.revertedWith('ERR_BAD_PATH');
        });

        it('reverts when not profitable', async () => {
            await expect(rebalancerAsAlice.swap(
                bundleAsAlice.address,
                token0AsAlice.address,
                token1AsAlice.address,
                ethers.utils.parseEther('100'),
                '2000000000',
                [token1AsAlice.address, token2AsAlice.address, token0AsAlice.address]
            )).to.be.revertedWith('INSUFFICIENT_OUTPUT_AMOUNT');
        });

        it('reverts when oracle not setup', async () => {
            await priceOracle.setReferencePath(token0AsDeployer.address, [token0AsDeployer.address, token2AsDeployer.address]);
            await priceOracle.setReferencePath(token1AsDeployer.address, [token1AsDeployer.address, token2AsDeployer.address]);

            await routerAsAlice.swapExactTokensForTokens(
                ethers.utils.parseEther('90000'),
                ethers.utils.parseEther('0'),
                [token0AsAlice.address, token2AsAlice.address],
                await alice.getAddress(),
                '2000000000'
            );

            await expect(rebalancerAsAlice.swap(
                bundleAsAlice.address,
                token0AsAlice.address,
                token1AsAlice.address,
                ethers.utils.parseEther('100'),
                '2000000000',
                [token1AsAlice.address, token2AsAlice.address, token0AsAlice.address]
            )).to.be.revertedWith('ERR_REFERENCE_NOT_INITIALIZED');
        });

        it('reverts when path results in price gap', async () => {
            await priceOracle.setReferencePath(token0AsDeployer.address, [token0AsDeployer.address, token2AsDeployer.address]);
            await priceOracle.setReferencePath(token1AsDeployer.address, [token1AsDeployer.address, token2AsDeployer.address]);

            await routerAsAlice.swapExactTokensForTokens(
                ethers.utils.parseEther('90000'),
                ethers.utils.parseEther('0'),
                [token0AsAlice.address, token2AsAlice.address],
                await alice.getAddress(),
                '2000000000'
            );

            await increase(duration.hours(ethers.BigNumber.from('1')));

            await expect(rebalancerAsAlice.swap(
                bundleAsAlice.address,
                token0AsAlice.address,
                token1AsAlice.address,
                ethers.utils.parseEther('100'),
                '2000000000',
                [token1AsAlice.address, token3AsAlice.address, token0AsAlice.address]
            )).to.be.revertedWith('ERR_SWAP_OUT_OF_GAP');
        });

        it('succeeds for valid conditions', async () => {
            await controllerAsDeployer.setPremium(ethers.utils.parseEther('4').div(100));

            await priceOracle.setReferencePath(token0AsDeployer.address, [token0AsDeployer.address, token2AsDeployer.address]);
            await priceOracle.setReferencePath(token1AsDeployer.address, [token1AsDeployer.address, token2AsDeployer.address]);

            await routerAsAlice.swapExactTokensForTokens(
                ethers.utils.parseEther('90000'),
                ethers.utils.parseEther('0'),
                [token0AsAlice.address, token2AsAlice.address],
                await alice.getAddress(),
                '2000000000'
            );

            await increase(duration.hours(ethers.BigNumber.from('1')));

            await rebalancerAsAlice.swap(
                bundleAsAlice.address,
                token0AsAlice.address,
                token1AsAlice.address,
                ethers.utils.parseEther('100'),
                '2000000000',
                [token1AsAlice.address, token2AsAlice.address, token0AsAlice.address]
            );

            expect(await token0AsAlice.balanceOf(bundleAsAlice.address)).to.be.bignumber.and.eq('10725278369428828393756');
            expect(await token0AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq('10026053265392867849739');
            expect(await token1AsAlice.balanceOf(bundleAsAlice.address)).to.be.bignumber.and.eq('4951475539710833830000');
            expect(await token1AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq('50000000000000000000000');
        });
    });

    context('setters', async () => {
        it('reverts when non-controller tries to whitelist', async () => {
            await expect(rebalancerAsAlice.setWhitelist(bundleAsDeployer.address, false)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when non-controller tries to whitelist', async () => {
            await expect(rebalancerAsAlice.setGap(0)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when non-controller tries to whitelist', async () => {
            await expect(rebalancerAsAlice.setOracle(bundleAsDeployer.address)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when non-controller tries to whitelist', async () => {
            await expect(rebalancerAsAlice.setPremium(0)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });
    });
});

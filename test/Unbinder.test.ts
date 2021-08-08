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
    UpgradeableBeacon,
    UpgradeableBeacon__factory,
    Unbinder,
    Unbinder__factory,
    Rebalancer,
    Rebalancer__factory,
} from '../typechain';
import { duration } from './helpers/time';

chai.use(solidity);
const { expect } = chai;

describe('Unbinder', () => {
    // Contract as Signer
    let controllerAsDeployer: Controller;
    let controllerAsAlice: Controller;
    let token0AsDeployer: MockERC20;
    let token1AsDeployer: MockERC20;
    let token2AsDeployer: MockERC20;
    let token3AsDeployer: MockERC20;
    let token4AsDeployer: MockERC20;
    let bundleAsDeployer: Bundle;
    let bundleAsAlice: Bundle;
    let unbinderAsAlice: Unbinder;

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
        for (let i = 0; i < 5; i++) {
            const MockERC20 = (await ethers.getContractFactory('MockERC20', deployer)) as MockERC20__factory;
            const mockERC20 = (await upgrades.deployProxy(MockERC20, [`TOKEN${i}`, `TOKEN${i}`])) as MockERC20;
            await mockERC20.deployed();
            tokens.push(mockERC20);
        }

        token0AsDeployer = MockERC20__factory.connect(tokens[0].address, deployer);
        token1AsDeployer = MockERC20__factory.connect(tokens[1].address, deployer);
        token2AsDeployer = MockERC20__factory.connect(tokens[2].address, deployer);
        token3AsDeployer = MockERC20__factory.connect(tokens[3].address, deployer);
        token4AsDeployer = MockERC20__factory.connect(tokens[4].address, deployer);

        // Mint tokens
        await token0AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('100000'));
        await token1AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('50000'));
        await token2AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('200000'));
        await token3AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('100000'));
        await token4AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('100000'));

        // Deploy controller
        const Controller = await ethers.getContractFactory('Controller');
        controller = (await upgrades.deployProxy(Controller, [bundleFactory.address, router.address])) as Controller;
        await controller.deployed();

        // Deploy rebalancer
        const Rebalancer = await ethers.getContractFactory('Rebalancer');
        rebalancer = (await upgrades.deployProxy(Rebalancer, [router.address, controller.address])) as Rebalancer;
        await rebalancer.deployed();

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(controller.address);

        // Set rebalancer on controller as deployer for testing
        await controller.setRebalancer(await rebalancer.address);

        await controller.setDefaultWhitelist([
            tokens[0].address,
            tokens[1].address,
            tokens[2].address,
            tokens[3].address,
        ]);

        await controller.setDelay(duration.days(ethers.BigNumber.from('1')));

        controllerAsDeployer = Controller__factory.connect(controller.address, deployer);
        controllerAsAlice = Controller__factory.connect(controller.address, alice);

        // Deploy bundle
        await (await controllerAsDeployer.deploy('Test', 'TST')).wait();
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
        await token3AsDeployer.approve(router.address, ethers.constants.MaxUint256);
        await token4AsDeployer.approve(router.address, ethers.constants.MaxUint256);

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
            ethers.utils.parseEther('25000'),
            ethers.utils.parseEther('50000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            token3AsDeployer.address,
            token2AsDeployer.address,
            ethers.utils.parseEther('10000'),
            ethers.utils.parseEther('10000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            token3AsDeployer.address,
            token4AsDeployer.address,
            ethers.utils.parseEther('10000'),
            ethers.utils.parseEther('10000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        await router.addLiquidity(
            token0AsDeployer.address,
            token4AsDeployer.address,
            ethers.utils.parseEther('10000'),
            ethers.utils.parseEther('10000'),
            0,
            0,
            await deployer.getAddress(),
            '2000000000'
        );

        await token3AsDeployer.transfer(bundleAddr, ethers.utils.parseEther('1000'));
        await bundleAsDeployer.gulp(token3AsDeployer.address);
    });

    context('handling unbound tokens', async () => {
        it('reverts for token path mismatch', async () => {
            await expect(
                unbinderAsAlice.distributeUnboundToken(
                    token3AsDeployer.address,
                    ethers.utils.parseEther('1000'),
                    '2000000000',
                    [[token0AsDeployer.address, token1AsDeployer.address]]
                )
            ).to.be.revertedWith('ERR_TOKENS_MISMATCH');
        });

        it('reverts when given bad start', async () => {
            await expect(
                unbinderAsAlice.distributeUnboundToken(
                    token3AsDeployer.address,
                    ethers.utils.parseEther('1000'),
                    '2000000000',
                    [
                        [token3AsDeployer.address, token2AsDeployer.address, token0AsDeployer.address],
                        [token1AsDeployer.address, token2AsDeployer.address, token0AsDeployer.address],
                    ]
                )
            ).to.be.revertedWith('ERR_PATH_START');
        });

        it('reverts when given bad end', async () => {
            await expect(
                unbinderAsAlice.distributeUnboundToken(
                    token3AsDeployer.address,
                    ethers.utils.parseEther('1000'),
                    '2000000000',
                    [
                        [token3AsDeployer.address, token2AsDeployer.address, token0AsDeployer.address],
                        [token3AsDeployer.address, token2AsDeployer.address, token0AsDeployer.address],
                    ]
                )
            ).to.be.revertedWith('ERR_PATH_END');
        });

        it('succeeds with proper parameters', async () => {
            expect(await token3AsDeployer.balanceOf(unbinderAddr)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1000')
            );

            await unbinderAsAlice.distributeUnboundToken(
                token3AsDeployer.address,
                ethers.utils.parseEther('1000'),
                '2000000000',
                [
                    [token3AsDeployer.address, token2AsDeployer.address, token0AsDeployer.address],
                    [token3AsDeployer.address, token2AsDeployer.address, token1AsDeployer.address],
                ]
            );

            expect(await token3AsDeployer.balanceOf(unbinderAddr)).to.be.bignumber.and.eq('0');
            expect(await token3AsDeployer.balanceOf(bundleAddr)).to.be.bignumber.and.eq('0');
            expect(await token3AsDeployer.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(
                ethers.utils.parseEther('10')
            );
            expect(await token0AsDeployer.balanceOf(bundleAddr)).to.be.bignumber.and.eq('10465439372725751018643');
            expect(await token1AsDeployer.balanceOf(bundleAddr)).to.be.bignumber.and.eq('5211952505362428694386');
        });

        it('reverts when given path outside whitelist', async () => {
            await expect(
                unbinderAsAlice.distributeUnboundToken(
                    token3AsDeployer.address,
                    ethers.utils.parseEther('1000'),
                    '2000000000',
                    [
                        [token3AsDeployer.address, token4AsDeployer.address, token0AsDeployer.address],
                        [token3AsDeployer.address, token2AsDeployer.address, token1AsDeployer.address],
                    ]
                )
            ).to.be.revertedWith('ERR_BAD_PATH');
        });
    });

    context('setters', async () => {
        it('reverts when non-controller tries to set premium', async () => {
            await expect(unbinderAsAlice.setPremium(0)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when flag not changed for swap token', async () => {
            await expect(
                controller.setUnbinderSwapWhitelist([unbinderAddr], tokens[1].address, true)
            ).to.be.revertedWith('ERR_FLAG_NOT_CHANGED');
        });

        it('correctly removes swap tokens', async () => {
            await controller.setUnbinderSwapWhitelist([unbinderAddr], tokens[1].address, false);
            const swapWhitelist = await unbinderAsAlice.getSwapWhitelist();
            expect(swapWhitelist.length).to.eq(3);
            expect(swapWhitelist[0]).to.eq(tokens[0].address);
            expect(swapWhitelist[1]).to.eq(tokens[3].address);
            expect(swapWhitelist[2]).to.eq(tokens[2].address);
        });
    });

    context('getters', async () => {
        it('returns expected array of swap tokens', async () => {
            const swapWhitelist = await unbinderAsAlice.getSwapWhitelist();
            expect(swapWhitelist.length).to.eq(4);
            expect(swapWhitelist[0]).to.eq(tokens[0].address);
            expect(swapWhitelist[1]).to.eq(tokens[1].address);
            expect(swapWhitelist[2]).to.eq(tokens[2].address);
            expect(swapWhitelist[3]).to.eq(tokens[3].address);
        });
    });
});

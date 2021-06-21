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
    UpgradeableBeacon,
    UpgradeableBeacon__factory,
    Unbinder,
    Unbinder__factory,
    Rebalancer,
} from '../typechain';
import { duration, increase } from './helpers/time';

chai.use(solidity);
const { expect } = chai;

describe('Bundle', () => {
    // Contract as Signer
    let controllerAsDeployer: Controller;
    let token0AsDeployer: MockERC20;
    let token1AsDeployer: MockERC20;
    let token2AsDeployer: MockERC20;
    let token0AsAlice: MockERC20;
    let token1AsAlice: MockERC20;
    let token2AsAlice: MockERC20;
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

    let bundleAddr: string;
    let unbinderAddr: string;

    const setup = async () => {
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

        await controllerAsDeployer.setTargetDelta(bundleAddr, duration.days(ethers.BigNumber.from('1')));
    };

    beforeEach(async () => {
        [deployer, alice] = await ethers.getSigners();

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
            ethers.constants.AddressZero,
            controller.address,
            ethers.constants.AddressZero,
            await deployer.getAddress(),
        ])) as Rebalancer;
        await rebalancer.deployed();

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(controller.address);

        // Set rebalancer on controller as deployer for testing
        await controller.setRebalancer(await rebalancer.address);

        await controller.setDelay(duration.days(ethers.BigNumber.from('1')));

        controllerAsDeployer = Controller__factory.connect(controller.address, deployer);

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
        token0AsAlice = MockERC20__factory.connect(tokens[0].address, alice);
        token1AsAlice = MockERC20__factory.connect(tokens[1].address, alice);
        token2AsAlice = MockERC20__factory.connect(tokens[2].address, alice);

        // Mint tokens
        await token0AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('10000'));
        await token1AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('5000'));
        await token2AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('10000'));

        // Deploy bundle
        await (await controllerAsDeployer.deploy('Test', 'TST')).wait();
        bundleAddr = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.bundle;
        unbinderAddr = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.unbinder;
        bundleAsDeployer = Bundle__factory.connect(bundleAddr, deployer);
        bundleAsAlice = Bundle__factory.connect(bundleAddr, alice);
    });

    context('reindexing', async () => {
        it('unbinds token after threshold', async () => {
            // Approve transfers for bundle
            await token0AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token2AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await controllerAsDeployer.setup(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address, token2AsDeployer.address],
                [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000'), ethers.utils.parseEther('10000')],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1'), ethers.utils.parseEther('2')],
                await deployer.getAddress()
            );

            await controllerAsDeployer.setTargetDelta(bundleAddr, duration.days(ethers.BigNumber.from('1')));

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('50000'));
            await token2AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token2AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await increase(duration.days(ethers.BigNumber.from('1')));

            // Remove token
            await controllerAsDeployer.reindexTokens(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1')],
                [0, 0]
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
                ethers.utils.parseEther('500'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token2AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('4')
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
                ethers.utils.parseEther('500'),
            ]);

            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );
            expect(await bundleAsDeployer.isBound(token2AsDeployer.address)).to.eq(false);
            // Result of negligible rounding error
            expect(await token2AsDeployer.balanceOf(unbinderAddr)).to.be.bignumber.and.eq('10999999999999999999500');
            expect(await token2AsDeployer.balanceOf(token2AsDeployer.address)).to.be.bignumber.and.eq('0');
        });

        it('unbinds token after threshold via exit', async () => {
            // Approve transfers for bundle
            await token0AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token2AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await controllerAsDeployer.setup(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address, token2AsDeployer.address],
                [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000'), ethers.utils.parseEther('10000')],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1'), ethers.utils.parseEther('2')],
                await deployer.getAddress()
            );

            await controllerAsDeployer.setTargetDelta(bundleAddr, duration.days(ethers.BigNumber.from('1')));

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('50000'));
            await token2AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token2AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await increase(duration.days(ethers.BigNumber.from('1')));

            // Remove token
            await controllerAsDeployer.reindexTokens(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1')],
                [0, 0]
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
                ethers.utils.parseEther('500'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token2AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('4')
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.exitPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('400'),
                ethers.utils.parseEther('100'),
                ethers.utils.parseEther('400'),
            ]);

            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );
            expect(await bundleAsDeployer.isBound(token2AsDeployer.address)).to.eq(false);
            // Result of negligible rounding error
            expect(await token2AsDeployer.balanceOf(unbinderAddr)).to.be.bignumber.and.eq('10009999999999999996500');
            expect(await token2AsDeployer.balanceOf(token2AsDeployer.address)).to.be.bignumber.and.eq('0');
        });

        it('binds token after threshold', async () => {
            await setup();

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('50000'));
            await token2AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token2AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await increase(duration.days(ethers.BigNumber.from('1')));

            // Add new token
            await controllerAsDeployer.reindexTokens(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address, token2AsDeployer.address],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1'), ethers.utils.parseEther('2')],
                [0, 0, ethers.utils.parseEther('100')]
            );

            // Should be bound but not ready
            expect(await bundleAsDeployer.isReady(token2AsDeployer.address)).to.eq(false);
            expect(await bundleAsDeployer.isBound(token2AsDeployer.address)).to.eq(true);

            // Join pool as alice
            await bundleAsAlice.joinPool(ethers.utils.parseEther('10'), [
                ethers.utils.parseEther('1000'),
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('50'),
            ]);

            expect(await bundleAsDeployer.totalSupply()).to.eq(ethers.utils.parseEther('110'));

            expect(await bundleAsDeployer.isReady(token2AsDeployer.address)).to.eq(false);

            // Shouldn't allow withdrawals on non-ready tokens
            await expect(
                bundleAsAlice.exitPool(ethers.utils.parseEther('5'), [
                    ethers.utils.parseEther('400'),
                    ethers.utils.parseEther('200'),
                    ethers.utils.parseEther('50'),
                ])
            ).to.be.revertedWith('ERR_NOT_READY');

            // Can withdraw if only taking ready tokens
            await bundleAsAlice.exitPool(ethers.utils.parseEther('10'), [
                ethers.utils.parseEther('490'),
                ethers.utils.parseEther('240'),
                ethers.utils.parseEther('0'),
            ]);

            await bundleAsAlice.joinPool(ethers.utils.parseEther('400'), [
                ethers.utils.parseEther('40000'),
                ethers.utils.parseEther('20000'),
                ethers.utils.parseEther('400'),
            ]);

            expect(await token2AsAlice.balanceOf(bundleAsAlice.address)).to.eq('409201596806387225500');
            expect(await bundleAsAlice.getBalance(token2AsAlice.address)).to.eq('409201596806387225500');
            expect(await bundleAsDeployer.isReady(token2AsDeployer.address)).to.eq(true);
            // Accounting for 2% exit fee
            expect(await bundleAsDeployer.totalSupply()).to.eq(ethers.utils.parseEther('500.2'));

            await bundleAsAlice.exitPool(ethers.utils.parseEther('50'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
                ethers.utils.parseEther('40'),
            ]);

            expect(await token2AsAlice.balanceOf(bundleAsAlice.address)).to.eq('369115874608240535994');
            expect(await bundleAsAlice.getBalance(token2AsAlice.address)).to.eq('369115874608240535994');

            await increase(duration.days(ethers.BigNumber.from('1')));

            await bundleAsAlice.exitPool(ethers.utils.parseEther('50'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
                ethers.utils.parseEther('40'),
            ]);

            // Should reach expected denorms
            expect(await bundleAsAlice.getDenormalizedWeight(token2AsAlice.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2')
            );
            expect(await bundleAsAlice.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('5')
            );
        });

        it('updates weights linearly', async () => {
            await setup();

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );

            await increase(duration.days(ethers.BigNumber.from('1')));

            await controllerAsDeployer.reindexTokens(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('1'), ethers.utils.parseEther('1')],
                [0, 0]
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1.5')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2.5')
            );

            await increase(duration.hours(ethers.BigNumber.from('12')));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2')
            );
        });

        it('reverts with bad weights', async () => {
            await setup();

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );

            await increase(duration.days(ethers.BigNumber.from('1')));

            await expect(
                controllerAsDeployer.reindexTokens(
                    bundleAsDeployer.address,
                    [token0AsDeployer.address, token1AsDeployer.address],
                    [ethers.utils.parseEther('100'), ethers.utils.parseEther('1')],
                    [0, 0]
                )
            ).to.be.revertedWith('ERR_MAX_WEIGHT');
        });
    });

    context('reweighting', async () => {
        it('unbinds on 0 weight', async () => {
            // Approve transfers for bundle
            await token0AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token2AsDeployer.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await controllerAsDeployer.setup(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address, token2AsDeployer.address],
                [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000'), ethers.utils.parseEther('10000')],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1'), ethers.utils.parseEther('2')],
                await deployer.getAddress()
            );

            await controllerAsDeployer.setTargetDelta(bundleAddr, duration.days(ethers.BigNumber.from('1')));

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('50000'));
            await token2AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100000'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token2AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await increase(duration.days(ethers.BigNumber.from('1')));

            // Remove token
            await controllerAsDeployer.reweighTokens(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address, token2AsDeployer.address],
                [ethers.utils.parseEther('2'), ethers.utils.parseEther('1'), 0]
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
                ethers.utils.parseEther('500'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token2AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('4')
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
                ethers.utils.parseEther('500'),
            ]);

            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );
            expect(await bundleAsDeployer.isBound(token2AsDeployer.address)).to.eq(false);
            // Result of negligible rounding error
            expect(await token2AsDeployer.balanceOf(unbinderAddr)).to.be.bignumber.and.eq('10999999999999999999500');
            expect(await token2AsDeployer.balanceOf(token2AsDeployer.address)).to.be.bignumber.and.eq('0');
        });

        it('reweighs correctly when decreasing', async () => {
            await setup();

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );

            await increase(duration.days(ethers.BigNumber.from('1')));

            await controllerAsDeployer.reweighTokens(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('1'), ethers.utils.parseEther('1')]
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1.5')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2.5')
            );

            await increase(duration.hours(ethers.BigNumber.from('12')));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2')
            );
        });

        it('reweighs correctly when increasing', async () => {
            await setup();

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );

            await increase(duration.days(ethers.BigNumber.from('1')));

            await controllerAsDeployer.reweighTokens(
                bundleAsDeployer.address,
                [token0AsDeployer.address, token1AsDeployer.address],
                [ethers.utils.parseEther('3'), ethers.utils.parseEther('1')]
            );

            await increase(duration.hours(ethers.BigNumber.from('12')).sub(1));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2.5')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3.5')
            );

            await increase(duration.hours(ethers.BigNumber.from('12')));

            await bundleAsAlice.joinPool(ethers.utils.parseEther('5'), [
                ethers.utils.parseEther('500'),
                ethers.utils.parseEther('250'),
            ]);
            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('4')
            );
        });

        it('reverts with bad weights', async () => {
            await setup();

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            expect(await bundleAsDeployer.getDenormalizedWeight(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2')
            );
            expect(await bundleAsDeployer.getTotalDenormalizedWeight()).to.be.bignumber.and.eq(
                ethers.utils.parseEther('3')
            );

            await increase(duration.days(ethers.BigNumber.from('1')));

            await expect(
                controllerAsDeployer.reweighTokens(
                    bundleAsDeployer.address,
                    [token0AsDeployer.address, token1AsDeployer.address],
                    [ethers.utils.parseEther('100'), ethers.utils.parseEther('1')]
                )
            ).to.be.revertedWith('ERR_MAX_WEIGHT');
        });
    });

    context('unbound tokens', async () => {
        it('returns unbound tokens to unbinder', async () => {
            await setup();

            await token2AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('1000'));
            await token2AsDeployer.transfer(bundleAsDeployer.address, ethers.utils.parseEther('1000'));
            expect(await token2AsDeployer.balanceOf(bundleAsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1000')
            );
            await bundleAsDeployer.gulp(token2AsDeployer.address);
            expect(await token2AsDeployer.balanceOf(bundleAsDeployer.address)).to.be.bignumber.and.eq(0);
            expect(await token2AsDeployer.balanceOf(unbinderAddr)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('1000')
            );
        });

        it('updates balances for bound tokens', async () => {
            await setup();

            await token0AsDeployer.mint(await deployer.getAddress(), ethers.utils.parseEther('1000'));
            await token0AsDeployer.transfer(bundleAsDeployer.address, ethers.utils.parseEther('1000'));
            expect(await token0AsDeployer.balanceOf(bundleAsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('11000')
            );
            expect(await bundleAsDeployer.getBalance(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('10000')
            );
            await bundleAsDeployer.gulp(token0AsDeployer.address);
            expect(await token0AsDeployer.balanceOf(bundleAsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('11000')
            );
            expect(await bundleAsDeployer.getBalance(token0AsDeployer.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('11000')
            );
        });
    });

    context('user interaction', async () => {
        it('joins and leaves the pool', async () => {
            await setup();

            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await bundleAsAlice.joinPool(ethers.utils.parseEther('10'), [
                ethers.utils.parseEther('1000'),
                ethers.utils.parseEther('500'),
            ]);
            expect(await token0AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(0);
            expect(await token1AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(0);
            expect(await bundleAsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(
                ethers.utils.parseEther('10')
            );

            // Expect a 2% fee to be applied
            await bundleAsAlice.exitPool(ethers.utils.parseEther('10'), [
                ethers.utils.parseEther('980'),
                ethers.utils.parseEther('490'),
            ]);
            // Account for negligible rounding error, see balancer trail of bits audit for explanation
            expect(await token0AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(
                ethers.utils.parseEther('980').add(1000)
            );
            expect(await token1AsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(
                ethers.utils.parseEther('490').add(500)
            );
            expect(await bundleAsAlice.balanceOf(await alice.getAddress())).to.be.bignumber.and.eq(0);
            expect(await bundleAsAlice.balanceOf(controller.address)).to.be.bignumber.and.eq(
                ethers.utils.parseEther('2').div(10)
            );
            expect(await bundleAsAlice.balanceOf(await deployer.getAddress())).to.be.bignumber.and.eq(
                ethers.utils.parseEther('100')
            );

            // Should revert when retrying
            await expect(
                bundleAsAlice.exitPool(ethers.utils.parseEther('10'), [
                    ethers.utils.parseEther('980'),
                    ethers.utils.parseEther('490'),
                ])
            ).to.be.reverted;
        });

        it('reverts if pool not initialized', async () => {
            // Mint tokens
            await token0AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('1000'));
            await token1AsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('500'));

            // Approve transfers for bundle
            await token0AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);
            await token1AsAlice.approve(bundleAsDeployer.address, ethers.constants.MaxUint256);

            await expect(
                bundleAsAlice.joinPool(ethers.utils.parseEther('10'), [
                    ethers.utils.parseEther('1000'),
                    ethers.utils.parseEther('500'),
                ])
            ).to.be.reverted;
        });

        it('reverts when user sets swap fee', async () => {
            await expect(bundleAsAlice.setSwapFee(0)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when user sets streaming fee', async () => {
            await expect(bundleAsAlice.setStreamingFee(0)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when user sets rebalancable', async () => {
            await expect(bundleAsAlice.setRebalancable(false)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when user sets public swap', async () => {
            await expect(bundleAsAlice.setPublicSwap(false)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when user sets min balance', async () => {
            await expect(bundleAsAlice.setMinBalance(token0AsAlice.address, 0)).to.be.revertedWith(
                'ERR_NOT_CONTROLLER'
            );
        });

        it('reverts when user sets exit fee', async () => {
            await expect(bundleAsAlice.setExitFee(0)).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when user collects streaming fee', async () => {
            await expect(bundleAsAlice.collectStreamingFee()).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when setting up the pool', async () => {
            await expect(
                bundleAsAlice.setup(
                    [token0AsDeployer.address, token1AsDeployer.address],
                    [ethers.utils.parseEther('10000'), ethers.utils.parseEther('5000')],
                    [ethers.utils.parseEther('2'), ethers.utils.parseEther('1')],
                    await deployer.getAddress()
                )
            ).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when reweighting', async () => {
            await expect(
                bundleAsAlice.reweighTokens(
                    [token0AsDeployer.address, token1AsDeployer.address],
                    [ethers.utils.parseEther('1'), ethers.utils.parseEther('1')]
                )
            ).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts when reindexing', async () => {
            await expect(
                bundleAsAlice.reindexTokens(
                    [token0AsDeployer.address, token1AsDeployer.address],
                    [ethers.utils.parseEther('1'), ethers.utils.parseEther('1')],
                    [0, 0]
                )
            ).to.be.revertedWith('ERR_NOT_CONTROLLER');
        });

        it('reverts on swaps when not rebalancer', async () => {
            await expect(
                bundleAsAlice.swapExactAmountIn(
                    token0AsAlice.address,
                    ethers.utils.parseEther('1'),
                    token1AsAlice.address,
                    ethers.utils.parseEther('1'),
                    ethers.utils.parseEther('1')
                )
            ).to.be.revertedWith('ERR_NOT_PUBLIC');

            await expect(
                bundleAsAlice.swapExactAmountOut(
                    token0AsAlice.address,
                    ethers.utils.parseEther('1'),
                    token1AsAlice.address,
                    ethers.utils.parseEther('1'),
                    ethers.utils.parseEther('1')
                )
            ).to.be.revertedWith('ERR_NOT_PUBLIC');

            await setup();

            await expect(
                bundleAsAlice.swapExactAmountIn(
                    token0AsAlice.address,
                    ethers.utils.parseEther('1'),
                    token1AsAlice.address,
                    ethers.utils.parseEther('1'),
                    ethers.utils.parseEther('1')
                )
            ).to.be.revertedWith('ERR_NOT_REBALANCER');

            await expect(
                bundleAsAlice.swapExactAmountOut(
                    token0AsAlice.address,
                    ethers.utils.parseEther('1'),
                    token1AsAlice.address,
                    ethers.utils.parseEther('1'),
                    ethers.utils.parseEther('1')
                )
            ).to.be.revertedWith('ERR_NOT_REBALANCER');
        });
    });
});

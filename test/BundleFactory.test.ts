import { ethers } from "hardhat";
import { Signer } from "ethers";
import chai from "chai";
import { solidity } from "ethereum-waffle";
import "@openzeppelin/test-helpers";
import {
    Bundle,
    Bundle__factory,
    BundleFactory,
    BundleFactory__factory,
    UpgradeableBeacon,
    UpgradeableBeacon__factory,
    Unbinder,
    Unbinder__factory
} from "../typechain";

chai.use(solidity);
const { expect } = chai;

describe("BundleFactory", () => {
    // Contract as Signer
    let bundleFactoryAsDeployer: BundleFactory

    // Accounts
    let deployer: Signer;

    let bundle: Bundle;
    let bundleBeacon: UpgradeableBeacon;
    let unbinder: Unbinder;
    let unbinderBeacon: UpgradeableBeacon;
    let bundleFactory: BundleFactory;

    beforeEach(async() => {
        [deployer] = await ethers.getSigners();

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

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(await deployer.getAddress());

        bundleFactoryAsDeployer = BundleFactory__factory.connect(bundleFactory.address, deployer);
    });

    context('deploy', async() => {
        it('should have set control variables', async() => {
            expect(await bundleFactory.getController()).to.eq(await deployer.getAddress());
        });

        it('should deploy proxy contracts', async() => {
            await bundleFactory.deploy("Test", "TST");
            const bundle = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.bundle;
            const bundleContract = Bundle__factory.connect(bundle, deployer);
            const unbinder = (await bundleFactory.queryFilter(bundleFactory.filters.LogDeploy(null, null)))[0].args.unbinder;
            const unbinderContract = Unbinder__factory.connect(unbinder, deployer);

            // Test that the proxies behave like contracts at expected state
            expect(await bundleContract.isPublicSwap()).to.eq(false);
            expect(await unbinderContract.getBundle()).to.eq(ethers.constants.AddressZero);
        });
    });
});

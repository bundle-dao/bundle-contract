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
    UpgradeableBeacon,
    UpgradeableBeacon__factory,
    Unbinder,
    Unbinder__factory,
    Rebalancer,
    Rebalancer__factory
} from "../typechain";

chai.use(solidity);
const { expect } = chai;

describe("BundleFactory", () => {
    // Contract as Signer
    let bundleControllerAsDeployer: Controller;

    // Accounts
    let deployer: Signer;

    let bundle: Bundle;
    let bundleBeacon: UpgradeableBeacon;
    let unbinder: Unbinder;
    let unbinderBeacon: UpgradeableBeacon;
    let bundleFactory: BundleFactory;
    let controller: Controller;
    let rebalancer: Rebalancer;

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

        // Deploy controller
        const Controller = await ethers.getContractFactory("Controller");
        controller = await upgrades.deployProxy(Controller, [bundleFactory.address, ethers.constants.AddressZero]) as Controller;

        // Deploy controller
        const Rebalancer = await ethers.getContractFactory("Rebalancer");
        rebalancer = await upgrades.deployProxy(
            Rebalancer, 
            [ethers.constants.AddressZero, controller.address, ethers.constants.AddressZero]
        ) as Rebalancer;

        // Set unbinder and controller to deployer for testing
        await bundleFactory.setController(controller.address);
        await bundleFactory.setRebalancer(await deployer.getAddress());

        // Set rebalancer on controller
        await controller.setRebalancer(rebalancer.address);

        bundleControllerAsDeployer = Controller__factory.connect(bundleFactory.address, deployer);
    });
});

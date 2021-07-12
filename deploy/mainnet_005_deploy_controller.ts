import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, upgrades } from 'hardhat';
import { Controller__factory, Controller, BundleFactory__factory } from '../typechain';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    /* Deploy Parameters */
    const DEV_ADDR = '0x148cF46a5A9E8B31e37AbcD4720168062F81F4a0';
    const ROUTER = '0x10ED43C718714eb63d5aA57B78B54704E256024E';
    /* Deploy Parameters */

    if (network.name !== 'mainnet') {
        console.log('This deployment script should be run against mainnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    // Deploy Bundle Factory
    console.log('>> Deploying the Bundle Factory');
    await deploy('BundleFactory', {
        from: deployer,
        args: [(await deployments.get('UnbinderBeacon')).address, (await deployments.get('BundleBeacon')).address],
        log: true,
        deterministicDeployment: false,
    });

    const bundleFactory = BundleFactory__factory.connect(
        (await deployments.get('BundleFactory')).address,
        (await ethers.getSigners())[0]
    );

    // Deploy controller with testnet pancake router
    console.log('>> Deploying the proxied controller');
    const Controller = (await ethers.getContractFactory(
        'Controller',
        (
            await ethers.getSigners()
        )[0]
    )) as Controller__factory;
    const controller = (await upgrades.deployProxy(Controller, [
        (await deployments.get('BundleFactory')).address,
        ROUTER,
    ])) as Controller;
    await controller.deployed();
    console.log(`>> Controller: ${controller.address}`);

    console.log('>> Transferring ownership of controller to dev');
    await controller.transferOwnership(DEV_ADDR, { gasLimit: '500000' });
    console.log('✅ Done');

    console.log('>> Setting the controller on factory');
    await bundleFactory.setController(controller.address);
    console.log('✅ Done');

    console.log('>> Verifying BundleFactory');
    await hre.run('verify:verify', {
        address: (await deployments.get('BundleFactory')).address,
        constructorArguments: [
            (await deployments.get('UnbinderBeacon')).address,
            (await deployments.get('BundleBeacon')).address,
        ],
    });
    console.log('✅ Done');
};

export default deploy;
deploy.tags = ['Mainnet', 'Controller'];

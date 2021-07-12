import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { UpgradeableBeacon__factory } from '../typechain';
import { ethers } from 'hardhat';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    /* Deploy Parameters */
    const DEV_ADDR = '0x148cF46a5A9E8B31e37AbcD4720168062F81F4a0';
    /* Deploy Parameters */

    if (network.name !== 'mainnet') {
        console.log('This deployment script should be run against mainnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    // Deploy Bundle implementation
    console.log('>> Deploying Bundle');
    await deploy('Bundle', {
        from: deployer,
        log: true,
        deterministicDeployment: false,
    });

    // Deploy Bundle Beacon
    console.log('>> Deploying Bundle Beacon');
    await deploy('BundleBeacon', {
        from: deployer,
        contract: 'UpgradeableBeacon',
        args: [(await deployments.get('Bundle')).address],
        log: true,
        deterministicDeployment: false,
    });

    // Transfer Ownership
    const bundleBeacon = UpgradeableBeacon__factory.connect((await deployments.get('BundleBeacon')).address, (await ethers.getSigners())[0]);
    
    console.log('>> Transferring ownership of beacon to dev');
    await bundleBeacon.transferOwnership(DEV_ADDR, { gasLimit: '500000' });
    console.log('✅ Done');

    // Deploy Unbinder implementation
    console.log('>> Deploying Unbinder');
    await deploy('Unbinder', {
        from: deployer,
        log: true,
        deterministicDeployment: false,
    });

    // Deploy Unbinder Beacon
    console.log('>> Deploying Unbinder Beacon');
    await deploy('UnbinderBeacon', {
        from: deployer,
        contract: 'UpgradeableBeacon',
        args: [(await deployments.get('Unbinder')).address],
        log: true,
        deterministicDeployment: false,
    });

    // Transfer Ownership
    const unbinderBeacon = UpgradeableBeacon__factory.connect((await deployments.get('UnbinderBeacon')).address, (await ethers.getSigners())[0]);

    console.log('>> Transferring ownership of beacon to dev');
    await unbinderBeacon.transferOwnership(DEV_ADDR, { gasLimit: '500000' });
    console.log('✅ Done');

    console.log('>> Verifying Bundle Implementation');
    await hre.run('verify:verify', {
        address: (await deployments.get('Bundle')).address,
    });
    console.log('✅ Done');

    console.log('>> Verifying Bundle Beacon');
    await hre.run('verify:verify', {
        address: (await deployments.get('BundleBeacon')).address,
        constructorArguments: [(await deployments.get('Bundle')).address],
    });
    console.log('✅ Done');

    console.log('>> Verifying Unbinder Implementation');
    await hre.run('verify:verify', {
        address: (await deployments.get('Unbinder')).address,
    });
    console.log('✅ Done');

    console.log('>> Verifying Unbinder Beacon');
    await hre.run('verify:verify', {
        address: (await deployments.get('UnbinderBeacon')).address,
        constructorArguments: [(await deployments.get('Unbinder')).address],
    });
    console.log('✅ Done');
};

export default deploy;
deploy.tags = ['Mainnet', 'Beacon'];

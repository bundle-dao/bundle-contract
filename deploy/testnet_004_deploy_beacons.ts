import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    if (network.name !== 'testnet') {
        console.log('This deployment script should be run against testnet only');
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
deploy.tags = ['Testnet', 'TBeacon'];

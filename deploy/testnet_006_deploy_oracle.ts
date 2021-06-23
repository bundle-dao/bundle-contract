import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const FACTORY = '';
    const PEG = '';

    if (network.name !== 'testnet') {
        console.log('This deployment script should be run against testnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    // Deploy Bundle Factory
    console.log('>> Deploying the Oracle');
    await deploy('PriceORacle', {
        from: deployer,
        args: [(await deployments.get('UnbinderBeacon')).address, (await deployments.get('BundleBeacon')).address],
        log: true,
        deterministicDeployment: false,
    });

    console.log('>> Verifying Oracle');
    await hre.run('verify:verify', {
        address: (await deployments.get('PriceOracle')).address,
        constructorArguments: [FACTORY, PEG],
    });
    console.log('✅ Done');
};

export default deploy;
deploy.tags = ['Testnet', 'TOracle'];

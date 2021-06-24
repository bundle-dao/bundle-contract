import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const FACTORY = '0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc';
    const PEG = '0xe25075950309995A6D18d7Dfd5B34EF02028F059';

    if (network.name !== 'testnet') {
        console.log('This deployment script should be run against testnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    // Deploy Bundle Factory
    console.log('>> Deploying the Oracle');
    await deploy('PriceOracle', {
        from: deployer,
        args: [FACTORY, PEG],
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

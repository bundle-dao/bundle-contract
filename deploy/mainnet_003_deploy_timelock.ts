import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    /* Deploy Parameters */
    const DELAY = '172800'; // 2 days
    const DEV_ADDR = '0x148cF46a5A9E8B31e37AbcD4720168062F81F4a0';
    /* Deploy Parameters */

    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    if (network.name !== 'mainnet') {
        console.log('This deployment script should be run against mainnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    await deploy('Timelock', {
        from: deployer,
        args: [DEV_ADDR, DELAY],
        log: true,
        deterministicDeployment: false,
    });

    console.log('>> Verifying Timelock');
    await hre.run('verify:verify', {
        address: (await deployments.get('Timelock')).address,
        constructorArguments: [DEV_ADDR, DELAY],
    });
    console.log('✅ Done');
};

export default deploy;
deploy.tags = ['Mainnet', 'Timelock'];

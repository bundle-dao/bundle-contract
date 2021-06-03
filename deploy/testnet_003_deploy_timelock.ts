import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    /* Deploy Parameters */
    const DELAY = '172800'; // 2 days
    /* Deploy Parameters */

    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    if (network.name !== 'testnet') {
        console.log('This deployment script should be run against testnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    await deploy('Timelock', {
        from: deployer,
        args: [
            deployer,
            DELAY,
        ],
        log: true,
        deterministicDeployment: false,
    });

    console.log(">> Verifying MinterGuard");
    await hre.run("verify:verify", {
        address: (await deployments.get('Timelock')).address,
        constructorArguments: [
            deployer,
            DELAY,
        ],
    });
    console.log("✅ Done");
};

export default deploy;
deploy.tags = ['Testnet', 'TTimelock'];
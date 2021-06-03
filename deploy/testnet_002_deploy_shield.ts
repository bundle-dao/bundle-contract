import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    /* Deploy Parameters */
    const MINTER = '0x8435DF5A52D6Fc955d5e1F4ff28b77e67149C2eB';
    /* Deploy Parameters */

    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    if (network.name !== 'testnet') {
        console.log('This deployment script should be run against testnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    await deploy('MinterGuard', {
        from: deployer,
        args: [
            deployer,
            MINTER,
        ],
        log: true,
        deterministicDeployment: false,
    });

    console.log(">> Verifying MinterGuard");
    await hre.run("verify:verify", {
        address: (await deployments.get('MinterGuard')).address,
        constructorArguments: [
            deployer,
            MINTER,
        ],
    });
    console.log("✅ Done");
};

export default deploy;
deploy.tags = ['Testnet', 'TMinterGuard'];
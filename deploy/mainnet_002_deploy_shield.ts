import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    /* Deploy Parameters */
    const MINTER = '0xA54D10C6666172824Da54C0d90BcdE36B6dAbd85';
    const DEV_ADDR = '0x148cF46a5A9E8B31e37AbcD4720168062F81F4a0';
    /* Deploy Parameters */

    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    if (network.name !== 'mainnet') {
        console.log('This deployment script should be run against mainnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    await deploy('MinterGuard', {
        from: deployer,
        args: [DEV_ADDR, MINTER],
        log: true,
        deterministicDeployment: false,
    });

    console.log('>> Verifying MinterGuard');
    await hre.run('verify:verify', {
        address: (await deployments.get('MinterGuard')).address,
        constructorArguments: [DEV_ADDR, MINTER],
    });
    console.log('✅ Done');
};

export default deploy;
deploy.tags = ['Mainnet', 'MinterGuard'];

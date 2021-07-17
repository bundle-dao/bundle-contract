import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { BundleRouter__factory } from '../typechain';
import { ethers } from 'hardhat';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    /* Deploy Parameters */
    const DEV_ADDR = '0x148cF46a5A9E8B31e37AbcD4720168062F81F4a0';
    const ROUTER = '0x10ED43C718714eb63d5aA57B78B54704E256024E';
    /* Deploy Parameters */

    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    if (network.name !== 'mainnet') {
        console.log('This deployment script should be run against mainnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    console.log('>> Deploying BundleRouter');
    await deploy('BundleRouter', {
        from: deployer,
        args: [ROUTER],
        log: true,
        deterministicDeployment: false,
    });
    console.log('✅ Done');

    const bundleRouter = BundleRouter__factory.connect(
        (await deployments.get('BundleRouter')).address,
        (await ethers.getSigners())[0]
    );

    console.log('>> Transferring ownership of BundleRouter');
    await bundleRouter.transferOwnership(DEV_ADDR);
    console.log('✅ Done');

    console.log('>> Verifying BundleRouter');
    await hre.run('verify:verify', {
        address: (await deployments.get('BundleRouter')).address,
        constructorArguments: [ROUTER],
    });
    console.log('✅ Done');
};

export default deploy;
deploy.tags = ['Mainnet', 'BundleRouter'];

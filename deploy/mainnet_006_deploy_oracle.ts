import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { PriceOracle__factory } from '../typechain';
import { ethers } from 'hardhat';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    /* Deploy Parameters */
    const DEV_ADDR = '0x148cF46a5A9E8B31e37AbcD4720168062F81F4a0';
    const FACTORY = '0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73';
    const PEG = '0xe9e7cea3dedca5984780bafc599bd69add087d56';
    /* Deploy Parameters */

    if (network.name !== 'mainnet') {
        console.log('This deployment script should be run against mainnet only');
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
    console.log('✅ Done');

    // Transfer Ownership
    const priceOracle = PriceOracle__factory.connect((await deployments.get('PriceOracle')).address, (await ethers.getSigners())[0]);
    
    console.log('>> Transferring ownership of oracle to dev');
    await priceOracle.transferOwnership(DEV_ADDR, { gasLimit: '500000' });
    console.log('✅ Done');

    console.log('>> Verifying Oracle');
    await hre.run('verify:verify', {
        address: (await deployments.get('PriceOracle')).address,
        constructorArguments: [FACTORY, PEG],
    });
    console.log('✅ Done');
};

export default deploy;
deploy.tags = ['Mainnet', 'Oracle'];

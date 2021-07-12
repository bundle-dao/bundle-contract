import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, upgrades } from 'hardhat';
import { Controller, Controller__factory, Rebalancer, Rebalancer__factory } from '../typechain';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, network } = hre;

    /* Deploy Parameters */
    const DEV_ADDR = '0x148cF46a5A9E8B31e37AbcD4720168062F81F4a0';
    const CONTROLLER = '0x40e4Ac8148279C3Bf414fA035F5dAE919b443Db4';
    const ROUTER = '0x10ED43C718714eb63d5aA57B78B54704E256024E';
    /* Deploy Parameters */

    if (network.name !== 'mainnet') {
        console.log('This deployment script should be run against mainnet only');
        return;
    }

    // Deploy controller with testnet pancake router
    console.log('>> Deploying the proxied rebalancer');
    const Rebalancer = (await ethers.getContractFactory(
        'Rebalancer',
        (
            await ethers.getSigners()
        )[0]
    )) as Rebalancer__factory;
    const rebalancer = (await upgrades.deployProxy(Rebalancer, [ROUTER, CONTROLLER])) as Rebalancer;
    await rebalancer.deployed();
    console.log(`>> Rebalancer: ${rebalancer.address}`);

    const controller = Controller__factory.connect(CONTROLLER, (await ethers.getSigners())[0]) as Controller;

    console.log('>> Setting the rebalancer');
    await controller.setRebalancer(rebalancer.address);
    console.log('✅ Done');

    console.log('>> Setting the oracle');
    await controller.setOracle((await deployments.get('PriceOracle')).address);
    console.log('✅ Done');

    console.log('>> Transferring ownership of controller to dev');
    await controller.transferOwnership(DEV_ADDR, { gasLimit: '500000' });
    console.log('✅ Done');
};

export default deploy;
deploy.tags = ['Mainnet', 'Rebalancer'];

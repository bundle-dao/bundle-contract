import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, upgrades } from 'hardhat';
import { Controller, Controller__factory, Rebalancer, Rebalancer__factory } from '../typechain';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, network } = hre;
    const CONTROLLER = '0x078DcaBbDFEecC9a8f2166dbD3a280E295235abB';
    const ROUTER = '0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3';

    if (network.name !== 'testnet') {
        console.log('This deployment script should be run against testnet only');
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
};

export default deploy;
deploy.tags = ['Testnet', 'TRebalancer'];

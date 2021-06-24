import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { upgrades, ethers } from 'hardhat';
import { MockERC20, MockERC20__factory } from '../typechain';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { network } = hre;

    if (network.name !== 'testnet') {
        console.log('This deployment script should be run against testnet only');
        return;
    }

    // Deploy Token A
    const MockERC20 = (await ethers.getContractFactory(
        'MockERC20',
        (
            await ethers.getSigners()
        )[0]
    )) as MockERC20__factory;
    const tokenA = (await upgrades.deployProxy(MockERC20, [`TOKEN A`, `TKNA`])) as MockERC20;
    await tokenA.deployed();
    console.log(`>> Token A: ${tokenA.address}`);

    // Deploy Token B
    const tokenB = (await upgrades.deployProxy(MockERC20, [`TOKEN B`, `TKNB`])) as MockERC20;
    await tokenB.deployed();
    console.log(`>> Token B: ${tokenB.address}`);

    // Deploy Token C
    const tokenC = (await upgrades.deployProxy(MockERC20, [`TOKEN C`, `TKNC`])) as MockERC20;
    await tokenC.deployed();
    console.log(`>> Token C: ${tokenC.address}`);

    // Deploy Peg
    const peg = (await upgrades.deployProxy(MockERC20, [`PEG`, `PEG`])) as MockERC20;
    await peg.deployed();
    console.log(`>> Peg: ${peg.address}`);
};

export default deploy;
deploy.tags = ['Testnet', 'TTokens'];

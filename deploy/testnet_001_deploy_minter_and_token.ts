import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';
import { BundleToken__factory, Minter__factory } from '../typechain';

const deploy: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    /* Deploy Parameters */
    const REWARD_PER_BLOCK = ethers.utils.parseEther('20');
    const BONUS_MULTIPLIER = 3;
    const BONUS_END_BLOCK = '9300000';
    const BONUS_LOCK_BPS = '6666';
    const START_BLOCK = '9110000';
    const LOCK_START_RELEASE = '9110000';
    const LOCK_END_RELEASE = '9500000';
    /* Deploy Parameters */

    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;

    if (network.name !== 'testnet') {
        console.log('This deployment script should be run against testnet only');
        return;
    }

    const { deployer } = await getNamedAccounts();

    await deploy('BundleToken', {
        from: deployer,
        args: [
            LOCK_START_RELEASE,
            LOCK_END_RELEASE,
        ],
        log: true,
        deterministicDeployment: false,
    });

    const bundleToken = BundleToken__factory.connect(
        (await deployments.get('BundleToken')).address, (await ethers.getSigners())[0]);

    await deploy('Minter', {
        from: deployer,
        args: [
            bundleToken.address,
            deployer,
            REWARD_PER_BLOCK,
            START_BLOCK
        ],
        log: true,
        deterministicDeployment: false,
    });
    const minter = Minter__factory.connect(
        (await deployments.get('Minter')).address, (await ethers.getSigners())[0]);

    console.log(">> Transferring ownership of BundleToken from deployer to Minter");
    await bundleToken.transferOwnership(minter.address, { gasLimit: '500000' });
    console.log("✅ Done");

    console.log(`>> Set Minter bonus to BONUS_MULTIPLIER: "${BONUS_MULTIPLIER}", BONUS_END_BLOCK: "${BONUS_END_BLOCK}", LOCK_BPS: ${BONUS_LOCK_BPS}`);
    await minter.setBonus(BONUS_MULTIPLIER, BONUS_END_BLOCK, BONUS_LOCK_BPS);
    console.log("✅ Done");

    console.log(">> Verifying BundleToken");
    await hre.run("verify:verify", {
        address: (await deployments.get('BundleToken')).address,
        constructorArguments: [
          LOCK_START_RELEASE,
          LOCK_END_RELEASE
        ],
    });
    console.log("✅ Done");

    console.log(">> Verifying Minter");
    await hre.run("verify:verify", {
        address: (await deployments.get('Minter')).address,
        constructorArguments: [
            bundleToken.address,
            deployer,
            REWARD_PER_BLOCK,
            START_BLOCK
        ],
    });
    console.log("✅ Done");
};

export default deploy;
deploy.tags = ['Testnet', 'Minter'];
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import '@openzeppelin/test-helpers';
import { BundleToken, BundleToken__factory } from '../typechain';

chai.use(solidity);
const { expect } = chai;

describe('BundleToken', () => {
    // Contract as Signer
    let bundleTokenAsAlice: BundleToken;
    let bundleTokenAsBob: BundleToken;
    let bundleTokenAsCarol: BundleToken;
    let bundleTokenAsDeployer: BundleToken;

    // Accounts
    let deployer: Signer;
    let alice: Signer;
    let bob: Signer;
    let carol: Signer;

    let bundleToken: BundleToken;

    beforeEach(async () => {
        [deployer, alice, bob, carol] = await ethers.getSigners();

        // Setup Minter contract
        // Deploy BDL
        const BundleToken = (await ethers.getContractFactory('BundleToken', deployer)) as BundleToken__factory;
        bundleToken = await BundleToken.deploy(132, 137);
        await bundleToken.deployed();

        bundleTokenAsAlice = BundleToken__factory.connect(bundleToken.address, alice);
        bundleTokenAsBob = BundleToken__factory.connect(bundleToken.address, bob);
        bundleTokenAsCarol = BundleToken__factory.connect(bundleToken.address, carol);
        bundleTokenAsDeployer = BundleToken__factory.connect(bundleToken.address, deployer);
    });

    context('when transferring funds', async () => {
        it('should transfer delegates during token transfers', async () => {
            await bundleTokenAsDeployer.mint(await alice.getAddress(), ethers.utils.parseEther('100'));
            await bundleTokenAsAlice.delegate(await carol.getAddress());

            // Carol should have 100 votes delegated
            expect(await bundleToken.getCurrentVotes(await carol.getAddress())).to.be.bignumber.eq(
                ethers.utils.parseEther('100')
            );

            await bundleTokenAsAlice.transfer(await bob.getAddress(), ethers.utils.parseEther('100'));
            await bundleTokenAsBob.delegate(await carol.getAddress());

            // Carol should still have 100 votes delegated
            expect(await bundleToken.getCurrentVotes(await carol.getAddress())).to.be.bignumber.eq(
                ethers.utils.parseEther('100')
            );

            await bundleTokenAsAlice.delegate(await bob.getAddress());
            await bundleTokenAsBob.approve(await alice.getAddress(), ethers.utils.parseEther('100'));
            await bundleTokenAsAlice.transferFrom(
                await bob.getAddress(),
                await alice.getAddress(),
                ethers.utils.parseEther('100')
            );
            await bundleTokenAsAlice.delegate(await carol.getAddress());

            // Carol should still have 100 votes delegated
            expect(await bundleToken.getCurrentVotes(await carol.getAddress())).to.be.bignumber.eq(
                ethers.utils.parseEther('100')
            );
        });
    });
});

import { config as dotEnvConfig } from 'dotenv';
dotEnvConfig();

import { HardhatUserConfig } from 'hardhat/types';

import '@openzeppelin/hardhat-upgrades';
import '@typechain/hardhat';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-deploy';
import 'solidity-coverage';
import '@nomiclabs/hardhat-etherscan';

const config: HardhatUserConfig = {
    defaultNetwork: 'hardhat',
    networks: {
        hardhat: {
            chainId: 31337,
            gas: 12000000,
            blockGasLimit: 0x1fffffffffffff,
            allowUnlimitedContractSize: true,
            accounts: [
                {
                    privateKey: process.env.LOCAL_PRIVATE_KEY_1!,
                    balance: '10000000000000000000000',
                },
                {
                    privateKey: process.env.LOCAL_PRIVATE_KEY_2!,
                    balance: '10000000000000000000000',
                },
                {
                    privateKey: process.env.LOCAL_PRIVATE_KEY_3!,
                    balance: '10000000000000000000000',
                },
                {
                    privateKey: process.env.LOCAL_PRIVATE_KEY_4!,
                    balance: '10000000000000000000000',
                },
            ],
        },
        testnet: {
            url: 'https://data-seed-prebsc-1-s3.binance.org:8545',
            accounts: [process.env.BSC_TESTNET_PRIVATE_KEY!],
        },
        mainnet: {
            url: process.env.BSC_MAINNET_RPC,
            accounts: [process.env.BSC_MAINNET_PRIVATE_KEY!],
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
    },
    solidity: {
        version: '0.5.16',
        settings: {
            optimizer: {
                enabled: true,
                runs: 1,
            },
            evmVersion: 'istanbul',
            outputSelection: {
                '*': {
                    '': ['ast'],
                    '*': [
                        'evm.bytecode.object',
                        'evm.deployedBytecode.object',
                        'abi',
                        'evm.bytecode.sourceMap',
                        'evm.deployedBytecode.sourceMap',
                        'metadata',
                    ],
                },
            },
        },
    },
    paths: {
        sources: './contracts/5',
        tests: './test',
        cache: './cache',
        artifacts: './artifacts',
    },
    typechain: {
        outDir: './typechain',
        target: 'ethers-v5',
    },
    etherscan: {
        apiKey: process.env.BSCSCAN_API_KEY!,
    },
};

export default config;
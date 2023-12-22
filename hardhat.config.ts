import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import 'hardhat-gas-reporter';
import 'hardhat-deal';
import 'hardhat-deploy';
import 'dotenv/config';
require('dotenv').config();

require('hardhat-tracer');
require('@openzeppelin/hardhat-upgrades');

console.log(
	`https://white-evocative-emerald.matic.quiknode.pro/${process.env.QUIKNODE_API_KEY?.toString()}/`
);

const config: HardhatUserConfig = {
	namedAccounts: {
		deployer: 0,
	},
	solidity: {
		version: '0.8.19',
		settings: {
			optimizer: {
				enabled: true,
				runs: 1000,
			},
		},
	},
	etherscan: {
		apiKey: process.env.ETHERS_SCAN_API_KEY,
	},
	gasReporter: {
		currency: 'USD',
		enabled: false,
		coinmarketcap: process.env.COIN_MARKETCAP_API_KEY,
		gasPriceApi: 'https://api.etherscan.io/api?module=proxy&action=eth_gasPrice',
	},
	networks: {
		hardhat: {
			forking: {
				url: `https://white-evocative-emerald.matic.quiknode.pro/${process.env.QUIKNODE_API_KEY?.toString()}/`,
			},
		},
		buildbear: {
			url: `https://rpc.buildbear.io/${process.env.BUILDBEAR_NODE_ID}`,
			accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
		},
		polygon: {
			url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_API_KEY}`,
			accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
			gasPrice: 100000000000,
		},
	},
};

export default config;

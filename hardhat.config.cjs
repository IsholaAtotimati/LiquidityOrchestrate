// hardhat.config.cjs
require("@nomicfoundation/hardhat-toolbox");
require("hardhat-gas-reporter");
require("dotenv").config();
const { task } = require("hardhat/config");

/** @type import('hardhat/config').HardhatUserConfig */
const config = {
  solidity: {
    version: "0.8.26",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: false,
      evmVersion: "cancun",
    },
  },

  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.DEPLOYER_PRIVATE_KEY
        ? [process.env.DEPLOYER_PRIVATE_KEY]
        : [],
    },
    hardhat: {
    blockGasLimit: 30_000_000, // 🚨 VERY IMPORTANT
  },
  localhost: {
  url: "http://127.0.0.1:8546",
},
     unichainTest: {
      url: process.env.UNICHAIN_RPC_URL || "",
      chainId:  1301,          // replace with the correct chainId
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
    },

    arbitrumSepolia: {
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "",
      accounts: process.env.DEPLOYER_PRIVATE_KEY
        ? [process.env.DEPLOYER_PRIVATE_KEY]
        : [],
      chainId: 421614, // Arbitrum Sepolia
    },
    fork: {
      url: process.env.MAINNET_RPC_URL || "https://mainnet.infura.io/v3/5741534f26d042999a28f7afd1e61fd7",
      forking: {
        url: process.env.MAINNET_RPC_URL || "https://mainnet.infura.io/v3/5741534f26d042999a28f7afd1e61fd7",
        blockNumber: 19700000 // Optional: set a recent block for deterministic tests
      },
      accounts: process.env.DEPLOYER_PRIVATE_KEY
        ? [process.env.DEPLOYER_PRIVATE_KEY]
        : [],
      chainId: 1,
    },
  },

  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },

  typechain: {
    outDir: "typechain",
    target: "ethers-v6",
  },

  gasReporter: {
    enabled: true,
    currency: "USD",
    showMethodSig: true,
    showTimeSpent: true,
  },

  mocha: {
    require: ["./test/setup.js"],
  },
};

// --------------------------
// Custom Hardhat Task
// --------------------------
task("full-test", "Runs all unit, fuzz, integration tests and gas reports")
  .setAction(async (taskArgs, hre) => {
    console.log("Running all tests with gas reporting...");
    await hre.run("test");
  });

// Use single API key (Etherscan v2 style) and register Uniscan as a custom chain
config.etherscan = {
  apiKey: process.env.ETHERSCAN_API_KEY || "",
  customChains: [
    {
      network: "unichainTest",
      chainId: 1301,
      urls: {
        apiURL: "https://api.uniscan.xyz/api",
        browserURL: "https://uniscan.xyz",
      },
    },
  ],
};
module.exports = config;
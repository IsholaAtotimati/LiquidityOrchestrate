const { ethers } = require("ethers");
require('dotenv').config();

const POOL_MANAGER_ABI = [
  "function initialize((address,address,uint24,int24,address), uint160)",
  "function modifyLiquidity((address,address,uint24,int24,address),(int24,int24,int256,bytes32),bytes)"
];

async function main() {
  const rpc = process.env.RPC_URL || 'http://localhost:8545';
  const pk = process.env.PRIVATE_KEY;
  const poolManagerAddr = process.env.POOL_MANAGER_ADDRESS;
  const hookAddr = process.env.HOOK_ADDRESS;
  const token0 = process.env.TOKEN0_ADDRESS;
  const token1 = process.env.TOKEN1_ADDRESS;
  const amount = process.env.AMOUNT || ethers.parseEther('1');
  if (!pk || !poolManagerAddr || !hookAddr || !token0 || !token1) {
    console.error('Please set PRIVATE_KEY, POOL_MANAGER_ADDRESS, HOOK_ADDRESS, TOKEN0_ADDRESS and TOKEN1_ADDRESS in env');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(pk, provider);
  const pm = new ethers.Contract(poolManagerAddr, POOL_MANAGER_ABI, wallet);

  // PoolKey tuple: (currency0, currency1, fee, tickSpacing, hooks)
  const fee = Number(process.env.FEE || 3000);
  const tickSpacing = Number(process.env.TICK_SPACING || 60);
  const poolKey = [token0, token1, fee, tickSpacing, hookAddr];

  console.log('Initializing pool (low-level)');
  try {
    const tx = await pm.initialize(poolKey, ethers.BigInt(1) << 96);
    await tx.wait();
    console.log('initialize tx sent');
  } catch (err) {
    console.log('initialize failed (may be fine):', err.message || err);
  }

  const liquidity = process.env.LIQUIDITY || ethers.parseEther('1');
  const tickLower = Number(process.env.TICK_LOWER || -120);
  const tickUpper = Number(process.env.TICK_UPPER || 120);

  const lpParams = [tickLower, tickUpper, ethers.BigInt(liquidity), ethers.Zero];

  console.log('Calling modifyLiquidity to add LP...');
  const tx = await pm.modifyLiquidity(poolKey, lpParams, '0x');
  await tx.wait();
  console.log('modifyLiquidity complete');
}

main().catch((e) => { console.error(e); process.exit(1); });

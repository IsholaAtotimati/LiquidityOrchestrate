const { ethers } = require("ethers");
require('dotenv').config();

const POOL_MANAGER_ABI = [
  "function swap((address,address,uint24,int24,address),(bool,int256,uint160),bytes)"
];
const HOOK_ABI = [
  "function checkUpkeep(bytes) view returns (bool, bytes)"
];

async function main() {
  const rpc = process.env.RPC_URL || 'http://localhost:8545';
  const pk = process.env.PRIVATE_KEY;
  const poolManagerAddr = process.env.POOL_MANAGER_ADDRESS;
  const hookAddr = process.env.HOOK_ADDRESS;
  const token0 = process.env.TOKEN0_ADDRESS;
  const token1 = process.env.TOKEN1_ADDRESS;
  if (!pk || !poolManagerAddr || !hookAddr || !token0 || !token1) {
    console.error('Please set PRIVATE_KEY, POOL_MANAGER_ADDRESS, HOOK_ADDRESS, TOKEN0_ADDRESS and TOKEN1_ADDRESS in env');
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(pk, provider);
  const pm = new ethers.Contract(poolManagerAddr, POOL_MANAGER_ABI, wallet);
  const hook = new ethers.Contract(hookAddr, HOOK_ABI, provider);

  const poolKey = [token0, token1, Number(process.env.FEE || 3000), Number(process.env.TICK_SPACING || 60), hookAddr];

  let iterations = Number(process.env.ITERATIONS || 100);
  const amountSpecified = ethers.BigInt(process.env.SWAP_AMOUNT || ethers.parseEther('0.01'));

  for (let i = 0; i < iterations; i++) {
    // Call swap: zeroForOne = true means token0 -> token1
    try {
      const sp = [true, amountSpecified, 0];
      const tx = await pm.swap(poolKey, sp, '0x');
      await tx.wait();
      console.log(`swap #${i} executed`);
    } catch (err) {
      console.error('swap failed:', err.message || err);
    }

    // Check hook upkeep — if it reports upkeepNeeded, stop
    try {
      const [need] = await hook.checkUpkeep('0x');
      if (need) { console.log('hook needs update — stopping swaps'); break; }
    } catch (e) {
      console.log('checkUpkeep call failed (non-fatal):', e.message || e);
    }
  }
}

main().catch((e) => { console.error(e); process.exit(1); });

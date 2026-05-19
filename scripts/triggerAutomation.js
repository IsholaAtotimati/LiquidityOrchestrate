const { ethers } = require("ethers");
require('dotenv').config();

const HOOK_ABI = [
  "function checkUpkeep(bytes) view returns (bool, bytes)",
  "function performUpkeep(bytes)",
  "function rebalance(bytes32,uint256,uint256)"
];

async function main() {
  const rpc = process.env.RPC_URL || 'http://localhost:8545';
  const pk = process.env.PRIVATE_KEY;
  const hookAddr = process.env.HOOK_ADDRESS;
  if (!pk || !hookAddr) { console.error('Set PRIVATE_KEY and HOOK_ADDRESS'); process.exit(1); }
  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(pk, provider);
  const hook = new ethers.Contract(hookAddr, HOOK_ABI, wallet);

  // Try checkUpkeep to get performData
  const [need, data] = await hook.checkUpkeep('0x');
  console.log('upkeepNeeded:', need);
  if (need) {
    console.log('calling performUpkeep with performData');
    const tx = await hook.performUpkeep(data);
    await tx.wait();
    console.log('performUpkeep complete');
    return;
  }

  // Otherwise call rebalance directly — user must supply POOL_ID env var
  const pidHex = process.env.POOL_ID_BYTES32;
  if (!pidHex) { console.error('No performData and POOL_ID_BYTES32 not set — nothing to do'); process.exit(1); }
  console.log('calling rebalance(', pidHex, ',0,10)');
  const tx2 = await hook.rebalance(pidHex, 0, 10);
  await tx2.wait();
  console.log('rebalance tx complete');
}

main().catch((e) => { console.error(e); process.exit(1); });

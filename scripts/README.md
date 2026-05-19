Scripts for simple practical testing flows.

Environment variables (common):
- `RPC_URL` - JSON-RPC endpoint (default http://localhost:8545)
- `PRIVATE_KEY` - signer private key used for txs
- `POOL_MANAGER_ADDRESS` - deployed pool manager contract address
- `HOOK_ADDRESS` - deployed IdleLiquidityHookEnterprise address
- `TOKEN0_ADDRESS` / `TOKEN1_ADDRESS` - token addresses
- `FEE` - pool fee (default 3000)
- `TICK_SPACING` - tick spacing (default 60)

Usage examples:

Add liquidity:
```bash
RPC_URL=http://127.0.0.1:8545 PRIVATE_KEY=0x... POOL_MANAGER_ADDRESS=0x... HOOK_ADDRESS=0x... TOKEN0_ADDRESS=0x... TOKEN1_ADDRESS=0x... node scripts/addLiquidity.js
```

Force swaps (token0 -> token1) until the hook requests update:
```bash
RPC_URL=... PRIVATE_KEY=... POOL_MANAGER_ADDRESS=... HOOK_ADDRESS=... TOKEN0_ADDRESS=... TOKEN1_ADDRESS=... node scripts/forceSwaps.js
```

Trigger automation (calls `performUpkeep` when available, or `rebalance` with `POOL_ID_BYTES32` env):
```bash
RPC_URL=... PRIVATE_KEY=... HOOK_ADDRESS=... POOL_ID_BYTES32=0x... node scripts/triggerAutomation.js
```

Reverse price (token1 -> token0):
```bash
RPC_URL=... PRIVATE_KEY=... POOL_MANAGER_ADDRESS=... HOOK_ADDRESS=... TOKEN0_ADDRESS=... TOKEN1_ADDRESS=... node scripts/reversePrice.js
```

Notes:
- These scripts are minimal helpers for local/integration testing and assume the PoolManager and Hook expose the expected functions. They intentionally avoid changing production contract logic.
- Tune `SWAP_AMOUNT`, `ITERATIONS`, `LIQUIDITY` using env vars.

# IdleLiquidityHookEnterprise — Protocol Reference
# IdleLiquidityHookEnterprise — Protocol Reference


This document describes the `IdleLiquidityHookEnterprise` contract implemented in this repository. It follows Uniswap-style documentation conventions: short overview, contract reference, deployment, and usage examples.
This document describes the `IdleLiquidityHookEnterprise` contract implemented in this repository. It follows Uniswap-style documentation conventions: short overview, contract reference, deployment, and usage examples.


## Overview
## Overview


`IdleLiquidityHookEnterprise` is a Uniswap v4 hook that automatically moves out-of-range liquidity into a vault (or Aave) while tracking yield for LPs. When the position returns into range, the hook can redeploy liquidity and distribute accrued yield.
`IdleLiquidityHookEnterprise` is a Uniswap v4 hook that automatically moves out-of-range liquidity into a vault (or Aave) while tracking yield for LPs. When the position returns into range, the hook can redeploy liquidity and distribute accrued yield.


- File: [contracts/hooks/IdleLiquidityHookEnterprise.sol](contracts/hooks/IdleLiquidityHookEnterprise.sol#L1-L400)
- File: [contracts/hooks/IdleLiquidityHookEnterprise.sol](contracts/hooks/IdleLiquidityHookEnterprise.sol#L1-L400)
- Constructor: `constructor(address _poolManager)` — an `IPoolManager` address is required.
- Constructor: `constructor(address _poolManager)` — an `IPoolManager` address is required.


### Important details
### Important details


- Uses Uniswap v4 `BaseHook` and must be deployed to an address whose lower 14 bits encode desired hook permissions (see Uniswap docs on hook deployment). The hook validates its own address in `BaseHook` constructor (skipped on chainId 31337).
- Uses Uniswap v4 `BaseHook` and must be deployed to an address whose lower 14 bits encode desired hook permissions (see Uniswap docs on hook deployment). The hook validates its own address in `BaseHook` constructor (skipped on chainId 31337).
- Tracks `PositionInfo` per `PoolId` and LP address; supports moving liquidity into an ERC4626 vault or an Aave lending pool.
- Tracks `PositionInfo` per `PoolId` and LP address; supports moving liquidity into an ERC4626 vault or an Aave lending pool.


## Contract: Key functions
## Contract: Key functions


All signatures below reference the implementation in [contracts/hooks/IdleLiquidityHookEnterprise.sol](contracts/hooks/IdleLiquidityHookEnterprise.sol#L1-L400).
All signatures below reference the implementation in [contracts/hooks/IdleLiquidityHookEnterprise.sol](contracts/hooks/IdleLiquidityHookEnterprise.sol#L1-L400).


- `constructor(address _poolManager)` — initialises the BaseHook with the `IPoolManager` address.
- `constructor(address _poolManager)` — initialises the BaseHook with the `IPoolManager` address.


- `function registerPosition(PoolId pid, uint128 liquidity0, uint128 liquidity1, int24 lower, int24 upper)` — called by LPs to register a position tracked by the hook. Two liquidity parameters allow the LP to specify amounts for each asset side of a dual-token pool.
- `function registerPosition(PoolId pid, uint128 liquidity0, uint128 liquidity1, int24 lower, int24 upper)` — called by LPs to register a position tracked by the hook. Two liquidity parameters allow the LP to specify amounts for each asset side of a dual-token pool.


- `function deregisterPosition(PoolId pid, PoolKey calldata key)` — deregister a position and collect yield if idle.
- `function deregisterPosition(PoolId pid, PoolKey calldata key)` — deregister a position and collect yield if idle.


- `function claimYield(PoolId pid, PoolKey calldata key)` — claim accumulated yield for the caller.
- `function claimYield(PoolId pid, PoolKey calldata key)` — claim accumulated yield for the caller.


- `function setPoolConfigVault(PoolId pid, uint8 side, IERC4626 _vault, uint256 lpBP, uint256 protocolBP)` — owner-only: configure an ERC4626 vault for one side (0 or 1) of a pool; `lpBP + protocolBP == 10000`. Records the vault address and underlying asset in `poolConfig[pid].assets[side]`. The `side` parameter lets you select which token (currency0 or currency1) will be used for deposits/yield.
- `function setPoolConfigVault(PoolId pid, uint8 side, IERC4626 _vault, uint256 lpBP, uint256 protocolBP)` — owner-only: configure an ERC4626 vault for one side (0 or 1) of a pool; `lpBP + protocolBP == 10000`. Records the vault address and underlying asset in `poolConfig[pid].assets[side]`. The `side` parameter lets you select which token (currency0 or currency1) will be used for deposits/yield.


- `function setPoolConfigAave(PoolId pid, uint8 side, ILendingPool _lendingPool, IERC20 _aToken, address _asset, uint256 lpBP, uint256 protocolBP)` — owner-only: configure an Aave lending pool flow for one side of the pool; `side` must be 0 or 1. Records the specified aToken and asset in `poolConfig[pid].assets[side]`.
- `function setPoolConfigAave(PoolId pid, uint8 side, ILendingPool _lendingPool, IERC20 _aToken, address _asset, uint256 lpBP, uint256 protocolBP)` — owner-only: configure an Aave lending pool flow for one side of the pool; `side` must be 0 or 1. Records the specified aToken and asset in `poolConfig[pid].assets[side]`.

- `function setPoolConfigAaveSelective(PoolId pid, uint8 side, address asset, address pool, address aToken, uint256 lpShareBP, uint256 protocolShareBP, uint8 flags)` — owner-only: selective setter that updates only the fields indicated by the `flags` bitmask. Flags: bit0=asset/pool/aToken/strategy, bit1=lpShareBP, bit2=protocolShareBP. Use when callers need to avoid rewriting all storage slots.
- `function updateRates(PoolId pid, uint256 lpShareBP, uint256 protocolShareBP)` — owner-only: minimal helper that updates only the two BP slots for `pid` (fast common-case for rate changes).
- `function updateRatesBatch(PoolId[] pids, uint256[] lpShareBPs, uint256[] protocolShareBPs)` — owner-only: batch variant that updates rates for multiple pools in one transaction; amortizes per-call overhead and reduces gas per-pool when updating many pools.

Recommendation: prefer `updateRatesBatch` when changing rates for multiple pools at once. For single-pool updates call `updateRates`. If you must change token/strategy metadata, use `setPoolConfigAave` or `setPoolConfigAaveSelective` with the appropriate flags.


- `function setPriceFeed(address asset, AggregatorV3Interface feed)` — owner-only: associate a Chainlink price feed with an asset. Used for external analytics or valuation, but currently only stores the mapping and emits `PriceFeedUpdated`.
- `function setPriceFeed(address asset, AggregatorV3Interface feed)` — owner-only: associate a Chainlink price feed with an asset. Used for external analytics or valuation, but currently only stores the mapping and emits `PriceFeedUpdated`.


- `function getLatestPrice(address asset) public view returns (int256)` — read the latest answer from the configured feed for `asset`. Reverts if no feed is set.
- `function getLatestPrice(address asset) public view returns (int256)` — read the latest answer from the configured feed for `asset`. Reverts if no feed is set.


- `function getPositionValue(PoolId pid, address lp) external view returns (int256)` — helper returning a rough combined value for the LP's registered position based on liquidity amounts and the latest prices from configured feeds. Zero if feeds not set or assets not configured; useful for off-chain dashboards.
- `function getPositionValue(PoolId pid, address lp) external view returns (int256)` — helper returning a rough combined value for the LP's registered position based on liquidity amounts and the latest prices from configured feeds. Zero if feeds not set or assets not configured; useful for off-chain dashboards.


### Events
### Events


- `event PositionRegistered(address indexed lp, PoolId indexed pid, uint128 liquidity0, uint128 liquidity1)`
- `event PositionRegistered(address indexed lp, PoolId indexed pid, uint128 liquidity0, uint128 liquidity1)`
- `event PositionDeregistered(address indexed lp, PoolId indexed pid)`
- `event PositionDeregistered(address indexed lp, PoolId indexed pid)`
- `event PoolConfigUpdated(PoolId indexed pid, uint8 side, address asset, uint256 lpBP, uint256 protocolBP)`
- `event PoolConfigUpdated(PoolId indexed pid, uint8 side, address asset, uint256 lpBP, uint256 protocolBP)`
- `event PriceFeedUpdated(address indexed asset, address feed)` — emitted when owner ties a Chainlink feed to an asset.
- `event PriceFeedUpdated(address indexed asset, address feed)` — emitted when owner ties a Chainlink feed to an asset.
- `event LiquidityMovedToVault(address indexed lp, PoolId indexed pid, uint256 amount, uint256 shares)`
- `event LiquidityMovedToVault(address indexed lp, PoolId indexed pid, uint256 amount, uint256 shares)`
- `event YieldCollected(address indexed lp, PoolId indexed pid, uint256 lpYield, uint256 protocolYield)`
- `event YieldCollected(address indexed lp, PoolId indexed pid, uint256 lpYield, uint256 protocolYield)`

### Global Index Accounting

Positions now accrue yield using a global index model. Each pool/side maintains an `globalYieldIndex` that is updated whenever the hook collects profit from the underlying strategy (Aave or ERC4626). Idle liquidity is tracked in `totalIdleLiquidity` and only those funds participate in the index. LPs entering idle state have a snapshot of the current index and later earn `delta_index * liquidity / 1e18`. This design removes the need for per-position proportional math on every update and enables high‑performance accounting.

### LP Tracking

The hook maintains a list of all registered LPs (`trackedLPs`) so that tick-range checks can be performed for every position when ticks move. A separate `idleLPs` array contains only LPs currently considered idle, allowing efficient redeployment when positions come back in-range.


## PoolId and PoolKey
## PoolId and PoolKey


- `PoolId` is `bytes32`. In the v4-core types, `PoolIdLibrary.toId(PoolKey)` returns `keccak256(abi.encode(poolKey))`.
- `PoolId` is `bytes32`. In the v4-core types, `PoolIdLibrary.toId(PoolKey)` returns `keccak256(abi.encode(poolKey))`.
- Use the same encoding on clients to compute `PoolId` (the frontend includes a helper that ABI-encodes `(address,address,uint24,int24,address)` and keccak256's it).
- Use the same encoding on clients to compute `PoolId` (the frontend includes a helper that ABI-encodes `(address,address,uint24,int24,address)` and keccak256's it).


## Deployment notes
## Deployment notes


1. The hook's constructor validates its deployed address against `getHookPermissions()` by checking low bits of the address. To deploy a hook that passes the check, deploy using a deterministic CREATE2 address with the required low bits (see Uniswap hook deployment guide).
1. The hook's constructor validates its deployed address against `getHookPermissions()` by checking low bits of the address. To deploy a hook that passes the check, deploy using a deterministic CREATE2 address with the required low bits (see Uniswap hook deployment guide).
2. For quick testing, deploy onto a local Hardhat node (chainId 31337); `BaseHook` skips validation on that chain id.
2. For quick testing, deploy onto a local Hardhat node (chainId 31337); `BaseHook` skips validation on that chain id.


### Example: calling `setPoolConfigVault`
### Example: calling `setPoolConfigVault`


Vaults expose an `asset()` method; the hook will automatically record this address and use it when moving liquidity or paying yield. This lets you configure a pool to operate on the second token in the pair if desired. Using `ethers.js` with a signer that is the hook owner:
Vaults expose an `asset()` method; the hook will automatically record this address and use it when moving liquidity or paying yield. This lets you configure a pool to operate on the second token in the pair if desired. Using `ethers.js` with a signer that is the hook owner:


```js
```js
const hook = new ethers.Contract(hookAddress, hookAbi, signer);
const hook = new ethers.Contract(hookAddress, hookAbi, signer);
const tx = await hook.setPoolConfigVault(poolId, 0, vaultAddress, 9000, 1000); // side 0
const tx = await hook.setPoolConfigVault(poolId, 0, vaultAddress, 9000, 1000); // side 0
await tx.wait();
await tx.wait();
// later `await hook.poolConfig(poolId)` returns (vault, lendingPool, aToken, asset, strategy, lpBP, protocolBP)
// later `await hook.poolConfig(poolId)` returns (vault, lendingPool, aToken, asset, strategy, lpBP, protocolBP)
```
```


### Notes on owner-only functions
### Notes on owner-only functions


Functions that change configuration (`setPoolConfig*`) are `onlyOwner`. The owner is set as the deployer in the current `constructor` (Ownable).
Functions that change configuration (`setPoolConfig*`) are `onlyOwner`. The owner is set as the deployer in the current `constructor` (Ownable).


## Security considerations
## Security considerations


- Ensure `lpBP + protocolBP == 10000` to avoid reverts. Frontend includes client-side validation.
- Ensure `lpBP + protocolBP == 10000` to avoid reverts. Frontend includes client-side validation.
- Pool configuration functions now validate that provided vault, lending pool, aToken, and asset addresses are non-zero. A bad configuration will cause the hook callback (`afterSwap`) to revert, blocking swaps. Always set correct addresses or leave the pool unconfigured (`strategy == NONE`).
- Pool configuration functions now validate that provided vault, lending pool, aToken, and asset addresses are non-zero. A bad configuration will cause the hook callback (`afterSwap`) to revert, blocking swaps. Always set correct addresses or leave the pool unconfigured (`strategy == NONE`).
- The constructor uses `validateHookAddress` which asserts low-bit flags. Use deterministic deploy to satisfy flags or run tests on local network.
- The constructor uses `validateHookAddress` which asserts low-bit flags. Use deterministic deploy to satisfy flags or run tests on local network.

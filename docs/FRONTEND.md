# Frontend — Usage Guide

This document explains the static frontend shipped in this repository for interacting with the `IdleLiquidityHookEnterprise` contract. The UI is intentionally minimal and follows Uniswap docs conventions: a Quickstart, Features, Examples, and Troubleshooting.

## Quickstart

1. Serve the `frontend` folder with a static server (MetaMask blocks `file://`):

```bash
directory: cd frontend. then  run
npx http-server -p 8000 -c-1


2. Open `http://localhost:8000` in a browser with MetaMask or another injected wallet.
3. Click `Connect Wallet` and accept MetaMask's connect prompt.
4. Load the contract ABI by either pasting the ABI JSON into the ABI textarea, or click `Load from artifacts` and provide the artifact path, for example:

```
artifacts/contracts/hooks/IdleLiquidityHookEnterprise.sol/IdleLiquidityHookEnterprise.json
```

5. Provide the contract address in the Contract section and the UI will use that address for subsequent interactions.

## Features

- Generic method UI: after loading an ABI the frontend renders callable functions (read vs tx) and lets you input arguments.
- Idle Hook Actions: helpers to compute `PoolId`, register/deregister positions, and claim yield by providing `PoolKey` JSON.
- Pool Config flows: dedicated UI to call `setPoolConfigVault` and `setPoolConfigAave` with client-side validation (ensures `lpBP + protocolBP == 10000`). The UI interprets the returned `strategy` field (0=NONE,1=ERC4626,2=AAVE).
- Artifact loader: a small convenience to fetch compiled ABI JSON from the repo's `artifacts` folder (works when served from the repo root).

## Examples

- Compute `PoolId`: fill `currency0`, `currency1`, `fee`, `tickSpacing`, and `hooks` then click `Compute PoolId`. The frontend ABI-encodes the PoolKey and computes keccak256.

- Register a position:
  - Load ABI + contract address
  - In Idle Hook Actions → Register Position: paste `PoolId`, provide `liquidity`, `lower` and `upper` ticks, click `Register Position`.

- Set Vault config (owner): fill `cfg_poolId`, `cfg_vault`, `cfg_vault_lpBP`, `cfg_vault_protocolBP` (must sum to 10000) and click `Set PoolConfig Vault`.

## Troubleshooting

- Reverts and owner-only functions: `setPoolConfig*` are `onlyOwner`. Connect the wallet that is the contract owner (deployer) or you will receive a revert. After configuration the frontend will display proper UI based on the selected strategy.
- Missing ABI: many UI elements require the ABI to be loaded first. If you see `Load an ABI to see methods`, load the ABI.
- CORS/Serving artifacts: when using `Load from artifacts`, serve from the repository root so the `artifacts` folder is reachable at `http://localhost:8000/artifacts/...`.

## Extending the frontend

The UI is intentionally modular. To add a new custom flow, edit `frontend/main.js` and add an HTML block to `frontend/index.html`.

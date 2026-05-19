# Environment variables for running tests and integration

The test suite supports both local unit tests and on-chain forked integration tests. The following environment variables are recognized by the tests and CI flows.

- `RUN_INTEGRATION` (optional): Set to `true` to enable on-fork integration tests that exercise real on-chain contracts. Default: `false`.
- `UNICHAIN_RPC_URL` (required for on-fork runs): RPC URL for the Unichain (Sepolia) fork provider. Example: `https://unichain-sepolia.g.alchemy.com/v2/<KEY>`.
- `POOL_MANAGER_ADDRESS` (required for on-fork runs): Address of the on-chain pool manager contract.
- `IDLE_LIQUIDITY_HOOK_ADDRESS` (required for on-fork runs): Address of the deployed `IdleLiquidityHookEnterprise` on-chain.
- `TOKEN0_ADDRESS`, `TOKEN1_ADDRESS` (required for strict integration checks): Token addresses used by the on-chain pool. If these are not set, integration tests that require real tokens will be skipped unless `RUN_INTEGRATION=true` and the values are present.
- `OWNER_ADDRESS` (optional): Fallback owner address used by some local flows. When an external on-chain hook is used, the tests attempt to detect the hook's actual owner via `hook.owner()`.

Notes
- Local unit tests will deploy lightweight `MockPoolManager` and local hooks when `IDLE_LIQUIDITY_HOOK_ADDRESS` or `POOL_MANAGER_ADDRESS` are not set.
- Integration tests are guarded: running the full on-chain flow requires `RUN_INTEGRATION=true` plus the necessary addresses (RPC, hook, tokens).
- If `RUN_INTEGRATION=true` but required env vars (RPC, tokens, hook) are missing, tests will error to avoid silent false positives.

Example `.env` snippet used in CI for on-fork runs:

UNICHAIN_RPC_URL="https://unichain-sepolia.g.alchemy.com/v2/<KEY>"
IDLE_LIQUIDITY_HOOK_ADDRESS="0x..."
POOL_MANAGER_ADDRESS="0x..."
TOKEN0_ADDRESS="0x..."
TOKEN1_ADDRESS="0x..."
OWNER_ADDRESS="0x..."

Usage
- Run local unit tests (fast):

```bash
forge test
```

- Run a single on-fork debug test (requires env vars above):

```bash
set -a && source .env && set +a && RUN_INTEGRATION=true forge test --match-test test_debug_flow -vvv --fork-url $UNICHAIN_RPC_URL
```

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice Position lifecycle state
enum Status {
    ACTIVE,
    IDLE,
    PROCESSING,
    FAILED
}

/// @notice Strategy type for idle liquidity
enum Strategy {
    NONE,
    ERC4626,
    AAVE
}

/// @notice Configuration for a single asset side
struct AssetConfig {
    // --- Strategy targets ---
    IERC4626 vault; // ERC4626 vault
    IPool aavePool; // Aave v3 pool
    // --- Tokens ---
    IERC20 aToken; // Aave interest-bearing token
    address asset; // underlying asset (USDC, WETH, etc.)
    // per-asset strategy implementation address (preferred)
    address strategyImpl;

    Strategy strategy;
}

/// @notice Pool-level configuration
struct PoolConfig {
    AssetConfig[2] assets;

    uint256 lpShareBP; // LP share of yield (basis points)
    uint256 protocolShareBP; // protocol fee (basis points)
}

/// @notice LP position tracking
struct Position {
    uint128 liquidity0;
    uint128 liquidity1;
    int24 lowerTick;
    int24 upperTick;
    Status status;
    uint256 lastYieldIndex0;
    uint256 lastYieldIndex1;
    uint256 accumulatedYield0;
    uint256 accumulatedYield1;
    uint256 vaultShares0;
    uint256 vaultShares1;
    uint256 aTokenPrincipal0;
    uint256 aTokenPrincipal1;
}

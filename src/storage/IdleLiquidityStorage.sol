// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Position, PoolConfig} from "../types/IdleLiquidityTypes.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

library IdleLiquidityStorage {
    struct Layout {
        // --- CORE STATE ---
        mapping(PoolId => PoolConfig) poolConfig;
        mapping(PoolId => mapping(address => Position)) positions;
        mapping(PoolId => address[]) trackedLPs;
        // fast lookup/indexing for tracked LPs to avoid O(n) existence checks and to enable
        // efficient removal: mapping to index in trackedLPs array and presence flag
        mapping(PoolId => mapping(address => uint256)) trackedLPIndex;
        mapping(PoolId => mapping(address => bool)) trackedLPPresent;

        // --- YIELD ---
        mapping(PoolId => uint256[2]) globalYieldIndex;
        mapping(PoolId => uint256[2]) totalIdleLiquidity;
        mapping(PoolId => uint256) lastYieldUpdate;

        // --- STRATEGY ACCOUNTING ---
        mapping(PoolId => uint256[2]) totalATokenPrincipal;
        mapping(PoolId => uint256[2]) totalVaultShares;

        // --- ORACLE ---
        mapping(address => AggregatorV3Interface) priceFeed;
        mapping(address => int256) lastGoodPrice;

        // --- REBALANCE CONTROL ---
        mapping(PoolId => bool) _needUpdate;
        mapping(PoolId => uint256) lastRebalanceBlock;
        // track last update-request block to debounce _needUpdate triggers
        mapping(PoolId => uint256) lastUpdateRequestBlock;
        mapping(PoolId => int24) lastObservedTick;
        mapping(PoolId => bool) hasObservedTick;
        uint256 rebalanceCooldownBlocks;
        int24 rebalanceTickThreshold;
        mapping(address => uint256) failureCount;

        uint256 rebalanceRewardETH;

        // --- ADMIN / CONFIG ---
        bool debugEmitUpdateRequested;
        uint256 maxLPsPerPool;
        mapping(address => bool) trustedAavePools;
        mapping(address => bool) trustedERC4626Vaults;
        address aaveStrategy;
        address erc4626Strategy;
        address strategyManager;

        PoolId[] allPools;
        mapping(PoolId => bool) poolExists;
        mapping(PoolId => bool) approvedPools;
        uint256 poolCursor;

        // --- SAFETY ---
        bool emergencyPaused;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("idle.liquidity.storage");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

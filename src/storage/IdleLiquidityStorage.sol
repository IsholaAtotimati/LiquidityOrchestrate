// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Position, PoolConfig} from "../types/IdleLiquidityTypes.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

contract IdleLiquidityStorage {
    // --- CORE STATE ---
    mapping(PoolId => PoolConfig) public poolConfig;
    mapping(PoolId => mapping(address => Position)) public positions;
    mapping(PoolId => address[]) public trackedLPs;
    // fast lookup/indexing for tracked LPs to avoid O(n) existence checks and to enable
    // efficient removal: mapping to index in trackedLPs array and presence flag
    mapping(PoolId => mapping(address => uint256)) public trackedLPIndex;
    mapping(PoolId => mapping(address => bool)) public trackedLPPresent;

    // --- YIELD ---
    mapping(PoolId => uint256[2]) public globalYieldIndex;
    mapping(PoolId => uint256[2]) public totalIdleLiquidity;
    mapping(PoolId => uint256) public lastYieldUpdate;

    // --- STRATEGY ACCOUNTING ---
    mapping(PoolId => uint256[2]) public totalATokenPrincipal;
    mapping(PoolId => uint256[2]) public totalVaultShares;

    // --- ORACLE ---
    mapping(address => AggregatorV3Interface) public priceFeed;
    mapping(address => int256) public lastGoodPrice;

    uint256 public constant ORACLE_MAX_DELAY = 1 hours;
    uint256 public constant MAX_DEVIATION_BP = 500; // 5%

    // --- REBALANCE CONTROL ---
    mapping(PoolId => bool) internal _needUpdate;
    mapping(PoolId => uint256) public lastRebalanceBlock;
    // track last update-request block to debounce _needUpdate triggers
    mapping(PoolId => uint256) public lastUpdateRequestBlock;

    uint256 public constant MIN_UPDATE_INTERVAL_BLOCKS = 3;

    uint256 public rebalanceRewardETH;

    // --- SAFETY ---
    bool public emergencyPaused;
}

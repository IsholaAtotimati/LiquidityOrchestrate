// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolConfig, AssetConfig, Strategy} from "../types/IdleLiquidityTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {StrategyManager} from "./StrategyManager.sol";

library PoolConfigManager {
    function setPoolConfigAave(
        mapping(PoolId => PoolConfig) storage poolConfig,
        mapping(PoolId => bool) storage poolExists,
        mapping(PoolId => bool) storage approvedPools,
        PoolId[] storage allPools,
        address strategyManager,
        address aaveStrategy,
        PoolId pid,
        uint8 side,
        address asset,
        address pool,
        address aToken,
        uint256 lpShareBP,
        uint256 protocolShareBP
    ) internal {
        require(asset != address(0), "ZERO_ASSET");
        require(pool != address(0), "ZERO_POOL");
        require(aToken != address(0), "ZERO_ATOKEN");

        AssetConfig storage ac = poolConfig[pid].assets[side];

        if (address(ac.vault) != address(0)) {
            ac.vault = IERC4626(address(0));
        }
        if (address(ac.aavePool) != pool) {
            ac.aavePool = IPool(pool);
        }
        if (address(ac.aToken) != aToken) {
            ac.aToken = IERC20(aToken);
        }
        if (ac.asset != asset) {
            ac.asset = asset;
        }
        if (strategyManager != address(0)) {
            address impl = StrategyManager(strategyManager).getImplementation(Strategy.AAVE);
            if (impl != address(0)) ac.strategyImpl = impl;
        } else if (aaveStrategy != address(0)) {
            ac.strategyImpl = aaveStrategy;
        }

        if (poolConfig[pid].lpShareBP != lpShareBP) {
            poolConfig[pid].lpShareBP = lpShareBP;
        }
        if (poolConfig[pid].protocolShareBP != protocolShareBP) {
            poolConfig[pid].protocolShareBP = protocolShareBP;
        }

        if (!poolExists[pid] && approvedPools[pid]) {
            allPools.push(pid);
            poolExists[pid] = true;
        }
    }

    function setPoolConfigAaveSelective(
        mapping(PoolId => PoolConfig) storage poolConfig,
        mapping(PoolId => bool) storage poolExists,
        mapping(PoolId => bool) storage approvedPools,
        PoolId[] storage allPools,
        address strategyManager,
        address aaveStrategy,
        PoolId pid,
        uint8 side,
        address asset,
        address pool,
        address aToken,
        uint256 lpShareBP,
        uint256 protocolShareBP,
        uint8 flags
    ) internal {
        require(aToken != address(0) || (flags & 1) == 0, "ZERO_ATOKEN");
        require(pool != address(0) || (flags & 1) == 0, "ZERO_POOL");
        require(asset != address(0) || (flags & 1) == 0, "ZERO_ASSET");

        AssetConfig storage ac = poolConfig[pid].assets[side];
        bool anyChange = false;

        if ((flags & 1) != 0) {
            if (address(ac.vault) != address(0)) {
                ac.vault = IERC4626(address(0));
            }
            if (address(ac.aavePool) != pool) {
                ac.aavePool = IPool(pool);
                anyChange = true;
            }
            if (address(ac.aToken) != aToken) {
                ac.aToken = IERC20(aToken);
                anyChange = true;
            }
            if (ac.asset != asset) {
                ac.asset = asset;
                anyChange = true;
            }
            if (strategyManager != address(0)) {
                address impl = StrategyManager(strategyManager).getImplementation(Strategy.AAVE);
                if (impl != address(0)) {
                    ac.strategyImpl = impl;
                    anyChange = true;
                }
            } else if (aaveStrategy != address(0)) {
                ac.strategyImpl = aaveStrategy;
                anyChange = true;
            }
        }

        if ((flags & 2) != 0) {
            if (poolConfig[pid].lpShareBP != lpShareBP) {
                poolConfig[pid].lpShareBP = lpShareBP;
                anyChange = true;
            }
        }

        if ((flags & 4) != 0) {
            if (poolConfig[pid].protocolShareBP != protocolShareBP) {
                poolConfig[pid].protocolShareBP = protocolShareBP;
                anyChange = true;
            }
        }

        if (anyChange && !poolExists[pid] && approvedPools[pid]) {
            allPools.push(pid);
            poolExists[pid] = true;
        }
    }

    function updateRates(
        mapping(PoolId => PoolConfig) storage poolConfig,
        mapping(PoolId => bool) storage poolExists,
        mapping(PoolId => bool) storage approvedPools,
        PoolId[] storage allPools,
        PoolId pid,
        uint256 lpShareBP,
        uint256 protocolShareBP
    ) internal {
        bool changed = false;
        if (poolConfig[pid].lpShareBP != lpShareBP) {
            poolConfig[pid].lpShareBP = lpShareBP;
            changed = true;
        }
        if (poolConfig[pid].protocolShareBP != protocolShareBP) {
            poolConfig[pid].protocolShareBP = protocolShareBP;
            changed = true;
        }
        if (changed && !poolExists[pid] && approvedPools[pid]) {
            allPools.push(pid);
            poolExists[pid] = true;
        }
    }

    function updateRatesBatch(
        mapping(PoolId => PoolConfig) storage poolConfig,
        mapping(PoolId => bool) storage poolExists,
        mapping(PoolId => bool) storage approvedPools,
        PoolId[] storage allPools,
        PoolId[] calldata pids,
        uint256[] calldata lpShareBPs,
        uint256[] calldata protocolShareBPs
    ) internal {
        uint256 n = pids.length;
        require(lpShareBPs.length == n && protocolShareBPs.length == n, "LENGTH_MISMATCH");
        for (uint256 i = 0; i < n; i++) {
            PoolId pid = pids[i];
            bool changed = false;
            if (poolConfig[pid].lpShareBP != lpShareBPs[i]) {
                poolConfig[pid].lpShareBP = lpShareBPs[i];
                changed = true;
            }
            if (poolConfig[pid].protocolShareBP != protocolShareBPs[i]) {
                poolConfig[pid].protocolShareBP = protocolShareBPs[i];
                changed = true;
            }
            if (changed && !poolExists[pid] && approvedPools[pid]) {
                allPools.push(pid);
                poolExists[pid] = true;
            }
        }
    }
}

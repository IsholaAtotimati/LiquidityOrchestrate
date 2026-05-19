// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Position, Status} from "../types/IdleLiquidityTypes.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

library PositionManager{
    function registerPosition(
        mapping(PoolId => mapping(address => Position)) storage positions,
        mapping(PoolId => address[]) storage trackedLPs,
        mapping(PoolId => mapping(address => bool)) storage isTracked,
        mapping(PoolId => uint256[2]) storage globalYieldIndex,
        PoolId pid,
        address lp,
        uint128 liquidity0,
        uint128 liquidity1,
        int24 lower,
        int24 upper
    ) internal {
        require(lp != address(0), "INVALID_LP");
        require(lower < upper, "INVALID_RANGE");
        require(liquidity0 > 0 || liquidity1 > 0, "ZERO_LIQUIDITY");

        Position storage pos = positions[pid][lp];

        // 🚨 strict: no overwrite
        require(
            pos.liquidity0 == 0 && pos.liquidity1 == 0,
            "POSITION_EXISTS"
        );

        // --- SET POSITION ---
        pos.liquidity0 = liquidity0;
        pos.liquidity1 = liquidity1;

        pos.lowerTick = lower;
        pos.upperTick = upper;

        pos.status = Status.ACTIVE;

        // initialize yield index
        pos.lastYieldIndex0 = globalYieldIndex[pid][0];
        pos.lastYieldIndex1 = globalYieldIndex[pid][1];

        // --- TRACK LP (O(1)) ---
        if (!isTracked[pid][lp]) {
            trackedLPs[pid].push(lp);
            isTracked[pid][lp] = true;
        }
    }
}
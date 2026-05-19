// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Position} from "../types/IdleLiquidityTypes.sol";

library LPRegistry {
    function registerLP(
        mapping(PoolId => address[]) storage trackedLPs,
        mapping(PoolId => mapping(address => bool)) storage trackedLPPresent,
        mapping(PoolId => mapping(address => uint256)) storage trackedLPIndex,
        PoolId pid,
        address lp,
        uint256 maxLPsPerPool
    ) internal {
        if (trackedLPPresent[pid][lp]) return;

        address[] storage lps = trackedLPs[pid];
        if (lps.length >= maxLPsPerPool) revert("LP_LIMIT");

        trackedLPPresent[pid][lp] = true;
        trackedLPIndex[pid][lp] = lps.length;
        lps.push(lp);
    }

    function clearPosition(
        mapping(PoolId => mapping(address => Position)) storage positions,
        mapping(PoolId => address[]) storage trackedLPs,
        mapping(PoolId => mapping(address => bool)) storage trackedLPPresent,
        mapping(PoolId => mapping(address => uint256)) storage trackedLPIndex,
        PoolId pid,
        address lp
    ) internal {
        delete positions[pid][lp];
        _removeTrackedLP(trackedLPs, trackedLPPresent, trackedLPIndex, pid, lp);
    }

    function pruneTrackedLPs(
        mapping(PoolId => address[]) storage trackedLPs,
        mapping(PoolId => mapping(address => bool)) storage trackedLPPresent,
        mapping(PoolId => mapping(address => uint256)) storage trackedLPIndex,
        mapping(PoolId => mapping(address => Position)) storage positions,
        PoolId pid,
        uint256 maxToPrune
    ) internal {
        address[] storage lps = trackedLPs[pid];
        uint256 i = 0;
        uint256 pruned = 0;

        while (i < lps.length && pruned < maxToPrune) {
            address lp = lps[i];
            Position storage pos = positions[pid][lp];
            bool isEmpty = pos.liquidity0 == 0 && pos.liquidity1 == 0 && pos.vaultShares0 == 0 && pos.vaultShares1 == 0 && pos.aTokenPrincipal0 == 0 && pos.aTokenPrincipal1 == 0;
            if (isEmpty) {
                delete positions[pid][lp];
                _removeTrackedLP(trackedLPs, trackedLPPresent, trackedLPIndex, pid, lp);
                pruned++;
            } else {
                i++;
            }
        }
    }

    function getTrackedLPs(
        mapping(PoolId => address[]) storage trackedLPs,
        PoolId pid
    ) internal view returns (address[] memory) {
        return trackedLPs[pid];
    }

    function _removeTrackedLP(
        mapping(PoolId => address[]) storage trackedLPs,
        mapping(PoolId => mapping(address => bool)) storage trackedLPPresent,
        mapping(PoolId => mapping(address => uint256)) storage trackedLPIndex,
        PoolId pid,
        address lp
    ) private {
        if (!trackedLPPresent[pid][lp]) return;

        address[] storage lps = trackedLPs[pid];
        uint256 idx = trackedLPIndex[pid][lp];
        address last = lps[lps.length - 1];
        lps[idx] = last;
        trackedLPIndex[pid][last] = idx;
        lps.pop();
        trackedLPPresent[pid][lp] = false;
        delete trackedLPIndex[pid][lp];
    }
}

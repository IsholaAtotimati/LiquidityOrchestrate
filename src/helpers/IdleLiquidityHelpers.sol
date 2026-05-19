// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library IdleLiquidityHelpers {
    function isOutOfRange(int24 currentTick, int24 lower, int24 upper) internal pure returns (bool) {
        return currentTick < lower || currentTick > upper;
    }
}

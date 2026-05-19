// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct ModifyLiquidityParams {
    address recipient;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidityDelta;
}

struct SwapParams {
    address recipient;
    bool zeroForOne;
    uint256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

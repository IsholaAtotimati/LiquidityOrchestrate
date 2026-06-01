// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LiquidityAdditionHelper
/// @notice Helper contract to add liquidity through PoolManager's unlock pattern
contract LiquidityAdditionHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;

    struct CallbackData {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        int24 tickSpacing;
        IHooks hook;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Initialize pool and add liquidity in one transaction
    function initializeAndAddLiquidity(
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        address hookAddr,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidityDelta
    ) external {
        Currency c0 = Currency.wrap(token0);
        Currency c1 = Currency.wrap(token1);

        CallbackData memory data = CallbackData({
            currency0: c0,
            currency1: c1,
            fee: fee,
            tickSpacing: tickSpacing,
            hook: IHooks(hookAddr),
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int256(liquidityDelta)
        });

        // Approve tokens to PoolManager
        IERC20(token0).approve(address(poolManager), type(uint256).max);
        IERC20(token1).approve(address(poolManager), type(uint256).max);

        // Call through unlock pattern
        poolManager.unlock(abi.encode(data, sqrtPriceX96));
    }

    /// @notice Callback for PoolManager unlock
    function unlockCallback(
        bytes calldata rawData
    ) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Unauthorized");

        (CallbackData memory data, uint160 sqrtPriceX96) = abi.decode(
            rawData,
            (CallbackData, uint160)
        );

        // Build PoolKey from data
        PoolKey memory key = PoolKey({
            currency0: data.currency0,
            currency1: data.currency1,
            fee: data.fee,
            tickSpacing: data.tickSpacing,
            hooks: data.hook
        });

        // 1. Initialize pool (might already exist)
        try
            poolManager.initialize(key, sqrtPriceX96)
        {} catch {}

        // 2. Add liquidity
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager
            .ModifyLiquidityParams({
                tickLower: data.tickLower,
                tickUpper: data.tickUpper,
                liquidityDelta: data.liquidityDelta,
                salt: bytes32(0)
            });

        poolManager.modifyLiquidity(key, params, "");

        return "";
    }
}

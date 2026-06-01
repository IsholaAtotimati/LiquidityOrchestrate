// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LiquidityAdditionHelper
/// @notice Helper contract to add liquidity through PoolManager's unlock pattern
contract LiquidityAdditionHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;

    struct CallbackData {
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidityDelta;
        address token0;
        address token1;
        address caller;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Initialize pool and add liquidity in one transaction
    function initializeAndAddLiquidity(
        PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidityDelta
    ) external {
        CallbackData memory data = CallbackData({
            key: key,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta,
            token0: Currency.unwrap(key.currency0),
            token1: Currency.unwrap(key.currency1),
            caller: msg.sender
        });

        // Approve tokens to PoolManager
        IERC20(data.token0).approve(address(poolManager), type(uint256).max);
        IERC20(data.token1).approve(address(poolManager), type(uint256).max);

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

        // 1. Initialize pool
        try
            poolManager.initialize(
                data.key,
                sqrtPriceX96
            )
        {} catch {}

        // 2. Add liquidity
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager
            .ModifyLiquidityParams({
                tickLower: data.tickLower,
                tickUpper: data.tickUpper,
                liquidityDelta: int256(data.liquidityDelta),
                salt: bytes32(0)
            });

        (, BalanceDelta delta) = poolManager.modifyLiquidity(data.key, params, "");

        // 3. Handle token transfers (settle balances)
        if (delta.amount0() != 0) {
            if (delta.amount0() > 0) {
                IERC20(data.token0).transferFrom(
                    data.caller,
                    address(poolManager),
                    uint256(int256(delta.amount0()))
                );
            }
        }

        if (delta.amount1() != 0) {
            if (delta.amount1() > 0) {
                IERC20(data.token1).transferFrom(
                    data.caller,
                    address(poolManager),
                    uint256(int256(delta.amount1()))
                );
            }
        }

        return "";
    }
}

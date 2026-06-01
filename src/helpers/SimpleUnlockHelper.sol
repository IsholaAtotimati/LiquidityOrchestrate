// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SimpleUnlockHelper
/// @notice Simplified helper to add liquidity through unlock callback
contract SimpleUnlockHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;
    address public caller;

    struct AddLiquidityData {
        PoolKey key;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidityDelta;
    }

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    /// @notice Add liquidity by going through unlock pattern
    function addLiquidity(
        PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidityDelta
    ) external {
        caller = msg.sender;

        // Encode the callback data
        AddLiquidityData memory data = AddLiquidityData({
            key: key,
            sqrtPriceX96: sqrtPriceX96,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidityDelta
        });

        // Call unlock
        poolManager.unlock(abi.encode(data));
    }

    /// @notice Callback from PoolManager
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Unauthorized");

        AddLiquidityData memory params = abi.decode(data, (AddLiquidityData));

        // Step 1: Try to initialize the pool (may already be initialized)
        try poolManager.initialize(params.key, params.sqrtPriceX96) {} catch {}

        // Step 2: Add liquidity
        IPoolManager.ModifyLiquidityParams memory modifyParams = IPoolManager
            .ModifyLiquidityParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: int256(params.liquidityDelta),
                salt: bytes32(0)
            });

        (,BalanceDelta delta) = poolManager.modifyLiquidity(params.key, modifyParams, "");

        // Step 3: Transfer tokens from caller to settle the balance
        // The hook will automatically call afterAddLiquidity and register the LP
        if (delta.amount0() > 0) {
            IERC20(Currency.unwrap(params.key.currency0)).transferFrom(
                caller,
                address(poolManager),
                uint256(int256(delta.amount0()))
            );
        }

        if (delta.amount1() > 0) {
            IERC20(Currency.unwrap(params.key.currency1)).transferFrom(
                caller,
                address(poolManager),
                uint256(int256(delta.amount1()))
            );
        }

        return "";
    }
}

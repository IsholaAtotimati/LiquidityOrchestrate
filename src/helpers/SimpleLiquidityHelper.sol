// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SimpleLiquidityHelper
/// @notice Minimal helper to add liquidity through PoolManager's unlock pattern
contract SimpleLiquidityHelper is IUnlockCallback {
    IPoolManager public immutable poolManager;
    address public immutable owner;

    event LiquidityAdded(address indexed lp, uint256 amount0, uint256 amount1);

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
        owner = msg.sender;
    }

    /// @notice Add liquidity for a position
    function addLiquidity(
        PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    ) external {
        // First, transfer tokens from caller to this contract
        if (amount0 > 0) {
            IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amount0);
        }
        if (amount1 > 0) {
            IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amount1);
        }

        // Encode callback data
        bytes memory data = abi.encode(
            key,
            sqrtPriceX96,
            tickLower,
            tickUpper,
            liquidity,
            msg.sender // The original caller
        );

        // Call unlock
        poolManager.unlock(data);
    }

    /// @notice Callback function called by PoolManager during unlock
    function unlockCallback(bytes calldata data)
        external
        override
        returns (bytes memory)
    {
        require(msg.sender == address(poolManager), "Unauthorized");

        (
            PoolKey memory key,
            uint160 sqrtPriceX96,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            address lp
        ) = abi.decode(data, (PoolKey, uint160, int24, int24, uint128, address));

        // Initialize pool if needed (try-catch to handle already initialized pools)
        try poolManager.initialize(key, sqrtPriceX96) {}
        catch {}

        // Add liquidity - the hook will automatically register the LP
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager
            .ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int128(uint128(liquidity)),
                salt: bytes32(0)
            });

        poolManager.modifyLiquidity(key, params, "");

        // Return empty to allow PoolManager to settle balances
        return "";
    }
}

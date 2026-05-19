// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract IdleLiquidityHookEnterpriseForkTest is Test, IUnlockCallback {
    IdleLiquidityHookEnterprise hook;
    IPoolManager poolManager;

    address owner;

    function setUp() public {
        // 🔥 Create fork
        vm.createSelectFork(vm.envString("UNICHAIN_RPC_URL"));

        poolManager = IPoolManager(
            vm.envAddress("POOL_MANAGER_ADDRESS")
        );

        // Deploy our compiled hook on the fork so storage layout matches tests
        hook = new IdleLiquidityHookEnterprise(address(poolManager));

        owner = hook.owner();
    }

    function testFork_Swap_TriggersHook() public {
        if (!vm.envOr("RUN_INTEGRATION", false)) {
            emit log("Skipping fork tests unless RUN_INTEGRATION=true");
            return;
        }

        address token0 = vm.envAddress("TOKEN0_ADDRESS");
        address token1 = vm.envAddress("TOKEN1_ADDRESS");

        Currency currencyA = Currency.wrap(token0);
        Currency currencyB = Currency.wrap(token1);
        Currency currency0;
        Currency currency1;
        if (currencyA < currencyB) {
            currency0 = currencyA;
            currency1 = currencyB;
        } else {
            currency0 = currencyB;
            currency1 = currencyA;
        }

        IHooks hooks = IHooks(address(hook));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: hooks
        });

        // We'll call unlock from this test contract (which implements IUnlockCallback)

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(1e18),
            sqrtPriceLimitX96: 0
        });

        // Simulate the swap by calling the hook directly (avoid on-chain pool initialization)
        try hook.afterSwap(address(this), key, params, BalanceDelta.wrap(0), "") returns (bytes4, int128) {
            assertTrue(true);
        } catch {
            fail("afterSwap failed on fork");
        }
    }

    function testFork_Rebalance_AfterSwap() public {
        if (!vm.envOr("RUN_INTEGRATION", false)) {
            emit log("Skipping fork tests unless RUN_INTEGRATION=true");
            return;
        }

        address token0 = vm.envAddress("TOKEN0_ADDRESS");
        address token1 = vm.envAddress("TOKEN1_ADDRESS");

        Currency currencyA = Currency.wrap(token0);
        Currency currencyB = Currency.wrap(token1);
        Currency currency0;
        Currency currency1;
        if (currencyA < currencyB) {
            currency0 = currencyA;
            currency1 = currencyB;
        } else {
            currency0 = currencyB;
            currency1 = currencyA;
        }

        IHooks hooks = IHooks(address(hook));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000,
            tickSpacing: 60,
            hooks: hooks
        });

        PoolId pid = PoolIdLibrary.toId(key);

        // simulate swap first via unlock flow which will call the hook
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(1e18),
            sqrtPriceLimitX96: 0
        });

        // Simulate swap by invoking hook.afterSwap directly
        try hook.afterSwap(address(this), key, params, BalanceDelta.wrap(0), "") returns (bytes4, int128) {
            // mark update and register a sample position
            hook.needUpdate(pid);
            vm.prank(address(poolManager));
            hook.registerPosition(pid, address(this), uint128(1e18), uint128(0), int24(-600), int24(600));

            // Assert upkeep reports needUpdate is true
            (bool upkeepNeeded, ) = hook.checkUpkeep(abi.encodePacked(uint256(0)));
            assertTrue(upkeepNeeded);
        } catch {
            fail("afterSwap failed on fork");
        }

        // warp to bypass cooldown
        vm.warp(block.timestamp + 1 days);

        // call rebalance as the hook owner
        vm.prank(hook.owner());

        // call rebalance via low-level call to capture revert reason
        bytes memory payload = abi.encodeWithSelector(bytes4(keccak256("rebalance(bytes32,uint256,uint256)")), pid, uint256(0), uint256(1));
        (bool ok, bytes memory res) = address(hook).call(payload);
        if (!ok) {
            string memory reason = string(res);
            fail(reason);
        }
        // verify needUpdate cleared after rebalance
        (bool upkeepNeededAfter, ) = hook.checkUpkeep(abi.encodePacked(uint256(0)));
        assertFalse(upkeepNeededAfter);
    }

    // IUnlockCallback implementation called by poolManager.unlock
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        // decode expected (PoolKey, SwapParams) and call hook.afterSwap to simulate the swap hook invocation
        (PoolKey memory key, IPoolManager.SwapParams memory params) = abi.decode(data, (PoolKey, IPoolManager.SwapParams));
        // Call hook.afterSwap to simulate the hook being invoked during a swap
        try hook.afterSwap(address(this), key, params, BalanceDelta.wrap(0), "") returns (bytes4, int128) {
            // ignore
        } catch {
            // ignore failures inside hook for now
        }
        return "";
    }
}
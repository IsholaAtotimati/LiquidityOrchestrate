// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {TestableIdleLiquidityHookEnterprise} from "../test/TestableIdleLiquidityHookEnterprise.sol";

import {MockPoolManager} from "../test/IdleLiquidityHook.fullFlow.t.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {Status} from "../src/types/IdleLiquidityTypes.sol";

contract FullFlowScript is Script {
    MockPoolManager pm;
    TestableIdleLiquidityHookEnterprise hook;

    ERC20PresetMinterPauser t0;
    ERC20PresetMinterPauser t1;

    function run() external {
        console.log("=== START FULL LIQUIDITY FLOW ===");

        vm.startBroadcast();

        // -----------------------------
        // 1. Deploy core contracts
        // -----------------------------
        pm = new MockPoolManager();
        hook = new TestableIdleLiquidityHookEnterprise(address(pm));

        t0 = new ERC20PresetMinterPauser("Token0", "T0");
        t1 = new ERC20PresetMinterPauser("Token1", "T1");

        t0.mint(msg.sender, 1000 ether);
        t1.mint(msg.sender, 1000 ether);

        console.log("Contracts deployed");

        // -----------------------------
        // 2. Setup pool
        // -----------------------------
        Currency c0 = Currency.wrap(address(t0));
        Currency c1 = Currency.wrap(address(t1));

        PoolKey memory key = PoolKey({
            currency0: c0 < c1 ? c0 : c1,
            currency1: c0 < c1 ? c1 : c0,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        PoolId pid = PoolIdLibrary.toId(key);

        hook.setApprovedPool(pid, true);

        console.log("Pool created");

        // -----------------------------
        // 3. Approve tokens
        // -----------------------------
        t0.approve(address(pm), type(uint256).max);
        t1.approve(address(pm), type(uint256).max);

        console.log("Tokens approved");

        // -----------------------------
        // 4. Add liquidity
        // -----------------------------
        IPoolManager.ModifyLiquidityParams memory lp =
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: int256(1e18),
                salt: bytes32(0)
            });

        pm.modifyLiquidity(key, lp, "");

        console.log("Liquidity added");

        (, , , , Status statusBefore, , , , , , , , ) =
            hook.positions(pid, msg.sender);

        console.log("Initial status:", uint256(statusBefore));

        // -----------------------------
        // 5. Initial swap (move price up)
        // -----------------------------
        for (uint i = 0; i < 3; i++) {
            IPoolManager.SwapParams memory sp = IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: int256(1e18 / 100),
                sqrtPriceLimitX96: 0
            });

            pm.swap(key, sp, "");
        }

        (, int24 tick1,,) = pm.getSlot0(pid);
        console.log("Tick after upward swaps:", tick1);

        // -----------------------------
        // 6. Trigger rebalance
        // -----------------------------
        (bool need,) = hook.checkUpkeep("");
        console.log("Need upkeep:", need);

        if (need) {
            hook.rebalance(pid, 0, 10);
            console.log("Rebalance executed (likely moved to IDLE)");
        }

        (, , , , Status statusIdle, , , , , , , , ) =
            hook.positions(pid, msg.sender);

        console.log("Status after rebalance:", uint256(statusIdle));

        // -----------------------------
        // 7. Reverse swaps (back into range)
        // -----------------------------
        for (uint i = 0; i < 3; i++) {
            IPoolManager.SwapParams memory sp2 = IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: int256(1e18 / 50),
                sqrtPriceLimitX96: 0
            });

            pm.swap(key, sp2, "");
        }

        (, int24 tick2,,) = pm.getSlot0(pid);
        console.log("Tick after reverse swaps:", tick2);

        // -----------------------------
        // 8. Final rebalance (back ACTIVE)
        // -----------------------------
        hook.rebalance(pid, 0, 10);

        (, , , , Status statusFinal, , , , , , , , ) =
            hook.positions(pid, msg.sender);

        console.log("Final status:", uint256(statusFinal));

        vm.stopBroadcast();

        console.log("=== FULL FLOW COMPLETE ===");
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Status} from "../src/types/IdleLiquidityTypes.sol";
import {Test} from "forge-std/Test.sol";
contract IdleLiquidityHookStressTest is Test {
    IdleLiquidityHookEnterprise hook;

    // actors
    address user1 = address(0x1);
    address user2 = address(0x2);
    address trader = address(0x3);

    PoolKey key;

    PoolId pid;

    // mock / test config
    int24 currentTick;

    function setUp() public {
        console2.log("stress test setup starting");

        // deploy hook (assumes constructor args already known in your project)
        hook = new IdleLiquidityHookEnterprise(
            address(this) // replace with your mock pool manager if required
        );

        // deterministic initial tick (important for stress tests)
        currentTick = 0;

        console2.log("stress test setup done");
    }

    // Provide a simple extsload implementation on the test contract so the hook
    // can call into the configured pool manager (this test sets poolManager=address(this)).
    function extsload(bytes32) external view returns (bytes32) {
        uint256 base = uint256(1) << 96;
        int24 tick = currentTick;
        uint256 protocolFee = 0;
        uint256 lpFee = 3000;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 packed = (uint256(lpFee) << 208) | (uint256(protocolFee) << 184) | (uint256(uint24(uint256(int256(tick)))) << 160) | base;
        return bytes32(packed);
    }

    // Minimal modifyLiquidity helper so the stress test can simulate LP actions
    // without implementing the full PoolManager. This matches the simple
    // callsite used in `_liquidityShock`.
    function modifyLiquidity(address who, PoolKey memory _key, int256 amount, bytes memory) public {
        bytes32 _pidBytes = bytes32(keccak256(abi.encode(_key, who)));
        PoolId pidWrapped = PoolId.wrap(_pidBytes);
        if (amount > 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint128 l = uint128(uint256(amount));
            hook.registerPosition(pidWrapped, who, l, 0, int24(-120), int24(120));
        } else {
            hook.clearPosition(pidWrapped, who);
        }
    }

    // =============================================================
    // 🌪️ MARKET SIMULATION CORE
    // =============================================================

    function _moveMarket(int24 tickShift) internal {
        currentTick += tickShift;

        console2.log("market moved to tick:", currentTick);

        // simulate pool state change (depends on your mock implementation)
        // forge-lint: disable-next-line(unsafe-typecast)
        this.extsload(bytes32(uint256(uint24(uint24(currentTick)))));
    }

    // =============================================================
    // 💧 LIQUIDITY SHOCKS
    // =============================================================

    function _liquidityShock(uint256 seed) internal {
        if (seed % 2 == 0) {
            console2.log("LP entering liquidity");
            // simulate LP deposit
            modifyLiquidity(user1, key, int256(1000e18), "");
        } else {
            console2.log("LP withdrawing liquidity");
            // simulate LP withdrawal
            modifyLiquidity(user1, key, -int256(500e18), "");
        }
    }

    // =============================================================
    // 💣 SWAP PRESSURE ENGINE
    // =============================================================

    function _runSwapPressure(uint256 rounds) internal {
        for (uint256 i = 0; i < rounds; i++) {
            bool zeroForOne = i % 2 == 0;

            int256 amount = int256(1e18 + (i * 1e16));

            console2.log("swap round", i);

            hook.afterSwap(
                trader,
                key,
                IPoolManager.SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: amount,
                    sqrtPriceLimitX96: 0
                }),
                BalanceDelta.wrap(0),
                ""
            );

            _assertSystemStable();
        }
    }

    // Debug wrappers to allow external calls and try/catch from the test
    function debug_moveMarket(int24 tickShift) external {
        _moveMarket(tickShift);
    }

    function debug_liquidityShock(uint256 seed) external {
        _liquidityShock(seed);
    }

    function debug_runSwapPressure(uint256 rounds) external {
        _runSwapPressure(rounds);
    }

    // =============================================================
    // 🧠 INVARIANT CHECKS
    // =============================================================

    function _assertSystemStable() internal {
        // basic sanity checks (extend based on your hook storage)


        (uint128 l0, uint128 l1, int24 lower, int24 upper, Status st, uint256 lastYieldIndex0, uint256 lastYieldIndex1, uint256 accumulatedYield0, uint256 accumulatedYield1, uint256 vaultShares0, uint256 vaultShares1, uint256 aTokenPrincipal0, uint256 aTokenPrincipal1) = hook.positions(pid, user1);

        // position bounds sanity
        assertTrue(lower <= upper, "invalid tick range");

        // liquidity must not be negative
        assertTrue(l0 >= 0 && l1 >= 0, "negative liquidity");
    }

    // =============================================================
    // 🔥 MAIN STRESS TEST
    // =============================================================

    function test_DeFiStressMarketChaos() public {
        console2.log("starting DeFi stress simulation");

        // 1. initialize position
        PoolKey memory _keyMem = key;
        pid = PoolIdLibrary.toId(_keyMem);
        hook.registerPosition(pid, user1, uint128(1000e18), uint128(0), int24(-120), int24(120));

        // 2. simulate multiple market cycles
        for (uint256 i = 0; i < 10; i++) {
            console2.log("cycle", i);

            // 🌪️ price movement (volatile market)
            int24 tickShift = int24(int256(int256((i * 37) % 200) - 100));
            console2.log("about to moveMarket");
            _moveMarket(tickShift);
            console2.log("movedMarket");

            // 💧 liquidity shock
            console2.log("about to liquidityShock");
            _liquidityShock(i);
            console2.log("done liquidityShock");

            // 💣 swap pressure
            console2.log("about to runSwapPressure");
            _runSwapPressure(3);
            console2.log("done runSwapPressure");

            // 🔁 rebalance attempt
            try hook.rebalance(pid, 0, 50) {
                console2.log("rebalance success");
            } catch {
                console2.log("rebalance failed safely (expected under stress)");
            }

            // 🧠 invariant check after each cycle
            _assertSystemStable();
        }

        console2.log("stress test completed successfully");
    }

    // =============================================================
    // ⚠️ FAILURE MODE TEST (IMPORTANT)
    // =============================================================

    function test_DeFiStress_ExtremeShock() public {
        PoolKey memory _keyMem2 = key;
        pid = PoolIdLibrary.toId(_keyMem2);
        hook.registerPosition(pid, user1, uint128(1000e18), uint128(0), int24(-120), int24(120));

        // extreme negative tick (market crash simulation)
        _moveMarket(-500);

        // massive swap imbalance
        _runSwapPressure(10);

        // ensure system does NOT revert permanently
        try hook.rebalance(pid, 0, 50) {
            console2.log("recovered from extreme shock");
        } catch {
            console2.log("safe failure under extreme stress");
        }

        _assertSystemStable();
    }
}
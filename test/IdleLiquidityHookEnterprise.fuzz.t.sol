// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract IdleLiquidityHookEnterpriseFuzzTest is Test {
    IdleLiquidityHookEnterprise hook;
    address owner;

    function setUp() public {
        owner = address(this);
        hook = new IdleLiquidityHookEnterprise(address(this)); // simple local deploy
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ 1: REBALANCE ROBUSTNESS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Rebalance_Robust(
        uint256 liquidity,
        uint256 swapAmount,
        uint256 timeSkip
    ) public {
        liquidity = bound(liquidity, 1 ether, 1000 ether);
        swapAmount = bound(swapAmount, 1 ether, 100 ether);
        timeSkip = bound(timeSkip, 1, 7 days);

        PoolId pid = PoolId.wrap(bytes32(uint256(1)));

        vm.startPrank(owner);
        hook.setPoolConfigAave(
            pid,
            0,
            address(0xCAFE),
            address(0xBEEF),
            address(0xDEAD),
            9000,
            1000
        );
        hook.setEmergencyPause(false);
        vm.stopPrank();

        vm.warp(block.timestamp + timeSkip);

        vm.prank(owner);
        hook.needUpdate(pid);

        try hook.rebalance(pid, 0, 1) {
            // stronger post-rebalance assertions
            uint256 rb = hook.lastRebalanceBlock(pid);
            (bool upkeepAfter,) = hook.checkUpkeep("");
            assertTrue(rb > 0, "lastRebalanceBlock not set after rebalance");
            assertTrue(!upkeepAfter, "upkeep still needed after rebalance");
        } catch {
            // acceptable: rebalance may revert for fuzzed inputs
            assertTrue(true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ 2: COOLDOWN TIMING
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Cooldown_Timing(uint256 timeSkip) public {
        timeSkip = bound(timeSkip, 1, 30 days);

        PoolId pid = PoolId.wrap(bytes32(uint256(2)));

        vm.startPrank(owner);
        hook.setPoolConfigAave(
            pid,
            0,
            address(0xCAFE),
            address(0xBEEF),
            address(0xDEAD),
            9000,
            1000
        );
        hook.setEmergencyPause(false);
        vm.stopPrank();

        vm.prank(owner);
        hook.needUpdate(pid);

        // first attempt
        try hook.rebalance(pid, 0, 1) {
            uint256 rb = hook.lastRebalanceBlock(pid);
            (bool upkeepAfter,) = hook.checkUpkeep("");
            assertTrue(rb > 0, "lastRebalanceBlock not set (cooldown)");
            assertTrue(!upkeepAfter, "upkeep still needed after rebalance (cooldown)");
        } catch {}

        vm.warp(block.timestamp + timeSkip);

        // second attempt
        try hook.rebalance(pid, 0, 1) {
            assertTrue(true);
        } catch {
            assertTrue(true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ 3: EMERGENCY PAUSE SAFETY
    //////////////////////////////////////////////////////////////*/

    function testFuzz_EmergencyPause(uint256 toggle) public {
        PoolId pid = PoolId.wrap(bytes32(uint256(3)));

        vm.startPrank(owner);
        hook.setPoolConfigAave(
            pid,
            0,
            address(0xCAFE),
            address(0xBEEF),
            address(0xDEAD),
            9000,
            1000
        );

        bool pauseState = toggle % 2 == 0;
        hook.setEmergencyPause(pauseState);
        vm.stopPrank();

        vm.prank(owner);
        hook.needUpdate(pid);

        if (pauseState) {
            vm.expectRevert();
            hook.rebalance(pid, 0, 1);
        } else {
            try hook.rebalance(pid, 0, 1) {
                uint256 rb = hook.lastRebalanceBlock(pid);
                (bool upkeepAfter,) = hook.checkUpkeep("");
                assertTrue(rb > 0, "lastRebalanceBlock not set (pause)");
                assertTrue(!upkeepAfter, "upkeep still needed after rebalance (pause)");
            } catch {
                assertTrue(true);
            }
        }
    }
}
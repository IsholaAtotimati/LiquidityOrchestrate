// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "./Mocks.sol";
import "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract OracleSafetyTest is Test {
    event ExternalCallFailed(address indexed target, string reason, bytes data);

    MockERC20 asset;
    MockERC20 aToken;
    MockAavePool aavePool;
    MockPoolManager pm;
    IdleLiquidityHookEnterprise hook;
    MockAggregator agg;

    PoolId pid = PoolId.wrap(bytes32(uint256(1)));
    address lp = address(0xBEEF);

    function setUp() public {
        asset = new MockERC20("Asset","AST");
        aToken = new MockERC20("AToken","ATK");
        aavePool = new MockAavePool(address(aToken), address(asset));
        pm = new MockPoolManager();
        hook = new IdleLiquidityHookEnterprise(address(pm));
        hook.setPoolConfigAave(pid, 0, address(asset), address(aavePool), address(aToken), 0, 0);
        hook.setTrustedAavePool(address(aavePool), true);
        // register position and mint underlying
        pm.callRegister(address(hook), pid, lp, 1_000_000 ether, 0, int24(1000), int24(2000));
        asset.mint(address(hook), 1_000_000 ether);
    }

    function test_staleTimestamp_skipsExecution() public {
        agg = new MockAggregator();
        // set answer but stale timestamp
        vm.warp(3 hours);
        agg.set(1000, block.timestamp - (2 hours));
        hook.setPriceFeed(address(asset), address(agg));

        uint256 before = hook.totalIdleLiquidity(pid, 0);
        vm.expectEmit(true, true, true, true);
        emit ExternalCallFailed(address(agg), "oracle-getprice-failed", bytes(""));
        hook.rebalanceSingleLPExternal(pid, lp, 0);
        uint256 afterVal = hook.totalIdleLiquidity(pid, 0);
        assertEq(before, afterVal);
    }

    function test_feedRevert_skipsExecution() public {
        agg = new MockAggregator();
        agg.setRevert(true);
        hook.setPriceFeed(address(asset), address(agg));
        uint256 before = hook.totalIdleLiquidity(pid, 0);
        vm.expectEmit(true, true, true, true);
        emit ExternalCallFailed(address(agg), "oracle-getprice-failed", bytes(""));
        hook.rebalanceSingleLPExternal(pid, lp, 0);
        uint256 afterVal = hook.totalIdleLiquidity(pid, 0);
        assertEq(before, afterVal);
    }

    function test_zeroPrice_skipsExecution() public {
        agg = new MockAggregator();
        agg.set(0, block.timestamp);
        hook.setPriceFeed(address(asset), address(agg));
        uint256 before = hook.totalIdleLiquidity(pid, 0);
        hook.rebalanceSingleLPExternal(pid, lp, 0);
        uint256 afterVal = hook.totalIdleLiquidity(pid, 0);
        assertEq(before, afterVal);
    }
}

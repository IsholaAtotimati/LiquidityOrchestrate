// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "./Mocks.sol";
import "../src/strategies/StrategyExecutor.sol";
import "../src/managers/StrategyManager.sol";
import "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Status} from "../src/types/IdleLiquidityTypes.sol";

contract DepositWithdrawTest is Test {
    MockERC20 asset;
    MockERC20 aToken;
    MockAavePool aavePool;
    MockPoolManager pm;
    StrategyExecutor executor;
    StrategyManager manager;
    IdleLiquidityHookEnterprise hook;
    MockAggregator agg;

    PoolId pid = PoolId.wrap(bytes32(uint256(1)));
    address lp = address(0xBEEF);

    function setUp() public {
        asset = new MockERC20("Asset","AST");
        aToken = new MockERC20("AToken","ATK");
        aavePool = new MockAavePool(address(aToken), address(asset));
        pm = new MockPoolManager();
        // deploy hook with poolManager = address(pm)
        hook = new IdleLiquidityHookEnterprise(address(pm));

        // deploy executor and manager
        executor = new StrategyExecutor();
        manager = new StrategyManager(address(this));
        manager.setExecutor(address(executor));

        // set strategy manager in hook (owner-only)
        hook.setStrategyManager(address(manager));
        // set pool config to use aave
        hook.setPoolConfigAave(pid, 0, address(asset), address(aavePool), address(aToken), 0, 0);
        // set price feed for asset
        agg = new MockAggregator();
        agg.set(1000, block.timestamp);
        hook.setPriceFeed(address(asset), address(agg));
        // mark pool trusted
        hook.setTrustedAavePool(address(aavePool), true);

        // register position via pool manager
        pm.callRegister(address(hook), pid, lp, 1_000_000 ether, 0, int24(1000), int24(2000));

        // mint asset to hook so deposit can be done
        asset.mint(address(hook), 1_000_000 ether);
    }

    function test_depositToAave_increasesIdleAccounting() public {
        // preconditions
        (uint256 before) = hook.totalIdleLiquidity(pid, 0);
        assertEq(before, 0);

        // trigger rebalance for lp (owner is this test contract)
        hook.rebalanceSingleLPExternal(pid, lp, 0);

        // after: totalIdleLiquidity increased
        uint256 afterIdle = hook.totalIdleLiquidity(pid, 0);
        assertGt(afterIdle, 0);

        // position liquidity should be zeroed and principal updated
        (uint128 liquidity0,
         uint128 liquidity1,
         int24 lowerTick,
         int24 upperTick,
         Status status,
         uint256 lastYieldIndex0,
         uint256 lastYieldIndex1,
         uint256 accumulatedYield0,
         uint256 accumulatedYield1,
         uint256 vaultShares0,
         uint256 vaultShares1,
         uint256 aTokenPrincipal0,
         uint256 aTokenPrincipal1) = hook.positions(pid, lp);

        assertEq(liquidity0, 0);
        assertGt(aTokenPrincipal0, 0);
    }
}

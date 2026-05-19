// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Status} from "../src/types/IdleLiquidityTypes.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";
import {MockAavePool} from "../contracts/MockAavePool.sol";
import {StrategyManager} from "../src/managers/StrategyManager.sol";
import {StrategyExecutor} from "../src/strategies/StrategyExecutor.sol";
import {AaveStrategy} from "../src/strategies/aave/AaveStrategy.sol";
// forge-lint: disable-next-line(unused-import)
// StateLibrary is intentionally not used in this test file; keep for reference
// import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract MockPoolManager {
    int24 public currentTick;

    constructor() { currentTick = 0; }

    function initialize(PoolKey calldata, uint160) external {}

    function modifyLiquidity(PoolKey calldata key, IPoolManager.ModifyLiquidityParams calldata params, bytes calldata) external {
        PoolId pid = PoolIdLibrary.toId(key);
        int256 liq = params.liquidityDelta;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 l = liq > 0 ? uint128(uint256(liq)) : 0;
        IdleLiquidityHookEnterprise(address(key.hooks)).registerPosition(pid, msg.sender, l, 0, params.tickLower, params.tickUpper);
    }

    function swap(PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata) external {
        // simulate price movement: token0->token1 (zeroForOne=true) increases tick, opposite decreases
        if (params.zeroForOne) {
            currentTick = currentTick + 60; // step
        } else {
            currentTick = currentTick - 60;
        }
        // notify hook using IPoolManager.SwapParams typed struct
        IPoolManager.SwapParams memory ip = IPoolManager.SwapParams({
            zeroForOne: params.zeroForOne,
            amountSpecified: params.amountSpecified,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });
        try key.hooks.afterSwap(address(this), key, ip, BalanceDelta.wrap(0), "") returns (bytes4, int128) {
        } catch {
            revert("hook afterSwap failed");
        }
    }

    // provide slot0 compatible view used by StateLibrary
    function getSlot0(PoolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee) {
        uint256 base = uint256(1) << 96;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 absTick = uint256(currentTick >= 0 ? uint256(uint24(uint256(int256(currentTick)))) : uint256(uint24(uint256(int256(-currentTick)))));
        uint256 sqrtPriceX = base + (absTick * (uint256(1) << 80) / 1000);
        return (uint160(sqrtPriceX), currentTick, uint24(0), uint24(3000));
    }

    // indicate support for extsload to satisfy hook probe
    function extsload(bytes32) external view returns (bytes32) {
        // pack data to mimic Pool.State.slot0 encoding expected by StateLibrary.getSlot0
        // layout (low->high): [160 bits sqrtPriceX96][24 bits tick][24 bits protocolFee][24 bits lpFee]
        uint256 base = uint256(1) << 96;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 absTick = uint256(currentTick >= 0 ? uint256(uint24(uint256(int256(currentTick)))) : uint256(uint24(uint256(int256(-currentTick)))));
        uint256 sqrtPriceX = base + (absTick * (uint256(1) << 80) / 1000);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 tickPart = (uint256(uint24(uint256(int256(currentTick)))) << 160);
        uint256 protocolFee = uint256(uint24(0)) << 184;
        uint256 lpFee = uint256(uint24(3000)) << 208;
        uint256 packed = sqrtPriceX | tickPart | protocolFee | lpFee;
        return bytes32(packed);
    }

    function setTick(int24 tick) external {
        currentTick = tick;
    }
}

contract IdleLiquidityHookFullFlowTest is Test {
    IdleLiquidityHookEnterprise public hook;
    MockPoolManager public pm;
    ERC20PresetMinterPauser public t0;
    ERC20PresetMinterPauser public t1;

    function setUp() public {
        pm = new MockPoolManager();
        hook = new IdleLiquidityHookEnterprise(address(pm));

        t0 = new ERC20PresetMinterPauser("T0", "T0");
        t1 = new ERC20PresetMinterPauser("T1", "T1");
        t0.mint(address(this), 1000 ether);
        t1.mint(address(this), 1000 ether);
    }

    function test_full_flow_simulation() public {
        Currency cA = Currency.wrap(address(t0));
        Currency cB = Currency.wrap(address(t1));
        Currency c0 = cA < cB ? cA : cB;
        Currency c1 = cA < cB ? cB : cA;
        IHooks hooksIface = IHooks(address(hook));
        PoolKey memory key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: hooksIface});
        PoolId pid = PoolIdLibrary.toId(key);

        // approve pool in hook so it will be tracked
        hook.setApprovedPool(pid, true);

        // approve token transfers to pool manager
        t0.approve(address(pm), type(uint256).max);
        t1.approve(address(pm), type(uint256).max);

        // add liquidity
        IPoolManager.ModifyLiquidityParams memory lp = IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: int256(1e18), salt: bytes32(0)});
        pm.modifyLiquidity(key, lp, "");

        // verify position stored and active
        (uint128 liq0, uint128 liq1, int24 lower, int24 upper, Status posStatus, uint256 lastYieldIndex0, uint256 lastYieldIndex1, uint256 accumulatedYield0, uint256 accumulatedYield1, uint256 vaultShares0, uint256 vaultShares1, uint256 aTokenPrincipal0, uint256 aTokenPrincipal1) = hook.positions(pid, address(this));
        assertTrue(posStatus == Status.ACTIVE, "position should be active after add");
        assertEq(lower, int24(-120));
        assertEq(upper, int24(120));

        // record initial tick
        (, int24 initialTick, , ) = pm.getSlot0(pid);

        // Force price movement: token0 -> token1 repeatedly to push tick up out of range
        for (uint i = 0; i < 3; i++) {
            IPoolManager.SwapParams memory sp = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: int256(1e18/100), sqrtPriceLimitX96: 0});
            pm.swap(key, sp, "");
        }
        (, int24 tickAfter, , ) = pm.getSlot0(pid);
        emit log_named_int("initialTick", initialTick);
        emit log_named_int("tickAfter", tickAfter);
        emit log_named_int("lower", lower);
        emit log_named_int("upper", upper);
        (uint128 liqa, uint128 liqb, int24 lowerA, int24 upperA, Status statusBefore, uint256 ly0a, uint256 ly1a, uint256 ay0a, uint256 ay1a, uint256 vs0a, uint256 vs1a, uint256 at0a, uint256 at1a) = hook.positions(pid, address(this));
        emit log_named_uint("posStatusBefore", uint256(uint8(statusBefore)));
        assertTrue(tickAfter > initialTick, "tick should increase after swaps");

        // hook should report upkeep needed
        (bool need, bytes memory performData) = hook.checkUpkeep("");
        assertTrue(need, "hook should request update after swaps");

        // inspect tracked LPs for this pool
        address[] memory lps = hook.getTrackedLPs(pid);
        emit log_named_uint("trackedLPs_len", lps.length);
        if (lps.length > 0) emit log_named_address("trackedLP0", lps[0]);
        assertTrue(lps.length > 0, "no tracked LPs");
        assertTrue(lps[0] == address(this), "tracked LP mismatch");

        // call rebalance to process all LPs (will clear _needUpdate if end==len)
        hook.rebalance(pid, 0, 10);

        // upkeep should be cleared
        (bool need2,) = hook.checkUpkeep("");
        assertTrue(!need2, "upkeep should be cleared after performUpkeep");

        // after rebalance, position likely moved to IDLE (outOfRange)
        (uint128 liq0b, uint128 liq1b, int24 lowerB, int24 upperB, Status statusAfter, uint256 ly0b, uint256 ly1b, uint256 ay0b, uint256 ay1b, uint256 vs0b, uint256 vs1b, uint256 at0b, uint256 at1b) = hook.positions(pid, address(this));
        emit log_named_uint("posStatusAfter", uint256(uint8(statusAfter)));
        assertTrue(statusAfter == Status.IDLE, "position should be IDLE after rebalance when out of range");

        // fast-forward blocks to allow update debounce and bypass execution cooldown
        vm.roll(block.number + 21);

        // Reverse price movement: token1 -> token0 to bring tick back into range
        for (uint i = 0; i < 3; i++) {
            IPoolManager.SwapParams memory sp = IPoolManager.SwapParams({zeroForOne: false, amountSpecified: int256(1e18/50), sqrtPriceLimitX96: 0});
            pm.swap(key, sp, "");
        }

        (, int24 tickFinal, , ) = pm.getSlot0(pid);
        assertTrue(tickFinal < tickAfter, "tick should decrease after reverse swaps");

        // test contract is owner of hook (deployer), so call rebalance directly
        hook.rebalance(pid, 0, 10);

        (uint128 liq0f, uint128 liq1f, int24 lowerF, int24 upperF, Status statusFinal, uint256 ly0f, uint256 ly1f, uint256 ay0f, uint256 ay1f, uint256 vs0f, uint256 vs1f, uint256 at0f, uint256 at1f) = hook.positions(pid, address(this));
        assertTrue(statusFinal == Status.ACTIVE, "position should be ACTIVE after re-entry");
    }

    function test_out_of_range_deposits_and_withdraws_to_aave() public {
        ERC20PresetMinterPauser asset = new ERC20PresetMinterPauser("A", "A");
        ERC20PresetMinterPauser aToken = new ERC20PresetMinterPauser("aA", "aA");
        MockAavePool aavePool = new MockAavePool(address(aToken));
        MockChainlinkFeed feed = new MockChainlinkFeed(1e18);

        uint256 amount = 1 ether;
        asset.mint(address(this), amount);
        asset.transfer(address(hook), amount);

        StrategyManager strategyManager = new StrategyManager(address(this));
        StrategyExecutor strategyExecutor = new StrategyExecutor();
        AaveStrategy aaveStrategy = new AaveStrategy();

        strategyManager.setExecutor(address(strategyExecutor));
        hook.setStrategyManager(address(strategyManager));
        hook.setAaveStrategy(address(aaveStrategy));

        Currency cA = Currency.wrap(address(asset));
        Currency cB = Currency.wrap(address(t1));
        Currency c0 = cA < cB ? cA : cB;
        Currency c1 = cA < cB ? cB : cA;
        IHooks hooksIface = IHooks(address(hook));
        PoolKey memory key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: hooksIface});
        PoolId pid = PoolIdLibrary.toId(key);

        hook.setApprovedPool(pid, true);
        hook.setTrustedAavePool(address(aavePool), true);
        hook.setPriceFeed(address(asset), address(feed));
        hook.setPoolConfigAave(pid, 0, address(asset), address(aavePool), address(aToken), 0, 0);

        vm.prank(address(pm));
        hook.registerPosition(pid, address(this), uint128(amount), 0, int24(100), int24(200));

        uint256 beforeHookAsset = asset.balanceOf(address(hook));
        assertEq(beforeHookAsset, amount, "hook should hold asset before idle move");

        hook.needUpdate(pid);
        hook.rebalance(pid, 0, 10);

        ( , , , , Status statusIdle, , , , , , , uint256 at0Idle, ) = hook.positions(pid, address(this));
        assertTrue(statusIdle == Status.IDLE, "position should be IDLE after out-of-range rebalance");
        assertEq(at0Idle, amount, "aToken principal should equal deposited amount");
        assertEq(asset.balanceOf(address(hook)), 0, "hook asset balance should be drained after deposit");
        assertEq(aToken.balanceOf(address(hook)), amount, "hook should receive aTokens from Aave deposit");

        vm.roll(block.number + 21);
        pm.setTick(150);

        emit log_named_uint("pool_asset_balance_before", asset.balanceOf(address(aavePool)));
        emit log_named_uint("hook_asset_balance_before", asset.balanceOf(address(hook)));
        emit log_named_uint("pool_aToken_balance_before", aToken.balanceOf(address(aavePool)));

        (, int24 tickInRange, , ) = pm.getSlot0(pid);
        assertEq(tickInRange, int24(150), "mock tick should be set to 150 before second rebalance");
        assertTrue(tickInRange >= int24(100) && tickInRange <= int24(200), "tick should be in range");

        vm.prank(address(hook));
        aToken.approve(address(aavePool), amount);
        uint256 snap = vm.snapshot();
        emit log_named_uint("hook_allowance_to_pool_before_withdraw", aToken.allowance(address(hook), address(aavePool)));
        emit log_named_uint("hook_aToken_balance_before_withdraw", aToken.balanceOf(address(hook)));
        vm.prank(address(aavePool));
        bool transferCheckOk = aToken.transferFrom(address(hook), address(aavePool), amount);
        emit log_named_uint("transferFrom_sanity_ok", transferCheckOk ? 1 : 0);
        vm.revertTo(snap);
        vm.prank(address(hook));
        uint256 directWithdrawn;
        try aavePool.withdraw(address(asset), amount, address(hook)) returns (uint256 result) {
            directWithdrawn = result;
            emit log_named_uint("direct_withdraw_ok", 1);
            emit log_named_uint("direct_withdrawn_amount", directWithdrawn);
        } catch Error(string memory reason) {
            emit log_named_string("direct_withdraw_reason", reason);
            revert("direct withdraw failed");
        } catch (bytes memory data) {
            emit log_named_uint("direct_withdraw_bad_data_len", data.length);
            if (data.length >= 4) {
                bytes4 selector;
                assembly { selector := mload(add(data, 32)) }
                if (selector == bytes4(keccak256("Error(string)"))) {
                    string memory decoded = decodeRevertReason(data);
                    emit log_named_string("direct_withdraw_reason", decoded);
                }
            }
            revert("direct withdraw failed");
        }
        emit log_named_uint("direct_withdrawn_amount", directWithdrawn);
        assertEq(asset.balanceOf(address(hook)), amount, "direct hook withdraw should restore asset");
        assertEq(asset.balanceOf(address(aavePool)), 0, "direct hook withdraw should empty pool asset");
        vm.revertTo(snap);

        hook.needUpdate(pid);
        hook.rebalance(pid, 0, 10);

        emit log_named_uint("pool_asset_balance_after", asset.balanceOf(address(aavePool)));
        emit log_named_uint("hook_asset_balance_after", asset.balanceOf(address(hook)));
        emit log_named_uint("failureCount_lp", hook.failureCount(address(this)));
        emit log_named_uint("failureCount_aave", hook.failureCount(address(aavePool)));
        emit log_named_uint("aToken_allowance_after_withdraw", aToken.allowance(address(hook), address(aavePool)));
        emit log_named_uint("hook_asset_balance_after_withdraw", asset.balanceOf(address(hook)));

        (, , , , Status statusActive, , , , , , , uint256 at0Active, ) = hook.positions(pid, address(this));
        emit log_named_uint("statusActive", uint256(uint8(statusActive)));
        assertTrue(statusActive == Status.ACTIVE, "position should return ACTIVE after in-range rebalance");
        assertEq(asset.balanceOf(address(hook)), amount, "hook asset balance should be restored after withdraw");
        assertEq(at0Active, amount, "aToken principal remains unchanged until active redeploy logic is implemented");
    }

        function test_debug_mock_aave_pool_withdraw_sanity() public {
        ERC20PresetMinterPauser asset = new ERC20PresetMinterPauser("A", "A");
        ERC20PresetMinterPauser aToken = new ERC20PresetMinterPauser("aA", "aA");
        MockAavePool aavePool = new MockAavePool(address(aToken));
        uint256 amount = 1 ether;

        asset.mint(address(this), amount);
        asset.approve(address(aavePool), amount);
        aavePool.supply(address(asset), amount, address(this), 0);
        assertEq(aToken.balanceOf(address(this)), amount, "expected aToken minted to test");

        aToken.approve(address(aavePool), amount);
        uint256 withdrawn;
        try aavePool.withdraw(address(asset), amount, address(this)) returns (uint256 result) {
            withdrawn = result;
            emit log_named_uint("debug_withdraw_ok", 1);
        } catch Error(string memory reason) {
            emit log_named_string("debug_withdraw_reason", reason);
            revert("withdraw failed");
        } catch (bytes memory data) {
            emit log_named_uint("debug_withdraw_data_len", data.length);
            revert("withdraw failed");
        }
        assertEq(withdrawn, amount, "expected withdraw to return amount");
        assertEq(asset.balanceOf(address(this)), amount, "expected asset returned to test account");
    }

    function test_debug_mock_aave_pool_transferFrom_sanity() public {
        ERC20PresetMinterPauser asset = new ERC20PresetMinterPauser("A", "A");
        ERC20PresetMinterPauser aToken = new ERC20PresetMinterPauser("aA", "aA");
        MockAavePool aavePool = new MockAavePool(address(aToken));
        uint256 amount = 1 ether;

        asset.mint(address(this), amount);
        asset.approve(address(aavePool), amount);
        aavePool.supply(address(asset), amount, address(this), 0);
        assertEq(aToken.balanceOf(address(this)), amount, "expected aToken minted to test");

        aToken.approve(address(aavePool), amount);
        emit log_named_uint("aToken_allowance", aToken.allowance(address(this), address(aavePool)));
        emit log_named_uint("aToken_balance", aToken.balanceOf(address(this)));

        vm.prank(address(aavePool));
        bool transferOk = aToken.transferFrom(address(this), address(aavePool), amount);
        emit log_named_uint("direct_transferFrom_result", transferOk ? 1 : 0);
        assertTrue(transferOk, "expected direct transferFrom as aavePool to succeed");
    }

    function decodeRevertReason(bytes memory data) internal pure returns (string memory) {
        if (data.length < 4) return "";
        bytes4 selector;
        assembly { selector := mload(add(data, 32)) }
        if (selector != bytes4(keccak256("Error(string)"))) return "";
        uint256 reasonLength;
        assembly { reasonLength := mload(add(data, 36)) }
        bytes memory reasonBytes = new bytes(reasonLength);
        for (uint256 i = 0; i < reasonLength; i++) {
            reasonBytes[i] = data[68 + i];
        }
        return string(reasonBytes);
    }
}

contract MockChainlinkFeed is AggregatorV3Interface {
    int256 public answer;

    constructor(int256 _answer) {
        answer = _answer;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}

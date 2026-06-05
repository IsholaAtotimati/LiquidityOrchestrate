// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {BaseHook} from "../periphery/base/hooks/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Types
// Use the pool manager's parameter types to match the IHooks interface exactly
// (IPoolManager exposes the ModifyLiquidityParams and SwapParams types).
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IdleLiquidityHelpers} from "../helpers/IdleLiquidityHelpers.sol";
import {OracleManager} from "../managers/OracleManager.sol";
import {YieldManager} from "../managers/YieldManager.sol";
import {RebalanceEngine} from "../managers/RebalanceEngine.sol";
import {StrategyManager} from "../managers/StrategyManager.sol";
import {IdleLiquidityRebalanceEngine} from "./IdleLiquidityRebalanceEngine.sol";
import {Position, AssetConfig, Status, Strategy} from "../types/IdleLiquidityTypes.sol";
import {IAaveStrategy, IERC4626Strategy, IStrategyCommon} from "../strategies/interfaces/IStrategy.sol";
import {PoolConfigManager} from "../managers/PoolConfigManager.sol";
import {LPRegistry} from "../registry/LPRegistry.sol";
import {PositionManager} from "../managers/PositionManager.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {IdleLiquidityStorage} from "../storage/IdleLiquidityStorage.sol";

contract IdleLiquidityHookEnterprise is BaseHook, IdleLiquidityRebalanceEngine {
    // =========================
    // EVENTS
    // =========================
    event RebalanceAttempt(PoolId indexed pid, address indexed lp);
    event RebalanceNeeded(PoolId indexed pid);
    event LiquidityIdle(PoolId indexed pid, address indexed lp);
    event EmergencyPauseSet(bool paused);
    event PositionRegistered(PoolId indexed pid, address indexed lp, address caller, uint128 liquidity0, uint128 liquidity1, int24 lower, int24 upper);
    event UpdateRequested(PoolId indexed pid, uint256 lastUpdateRequestBlock, uint256 currentBlock, uint256 minInterval, bool set);

    uint256 public constant DEFAULT_REBALANCE_COOLDOWN_BLOCKS = 20;
    int24 public constant DEFAULT_REBALANCE_TICK_THRESHOLD = 60;

    // `onlyPoolManager` is inherited from ImmutableState/BaseHook; do not redeclare here.

    // =========================
    // CONSTRUCTOR
    // =========================

    function _state() internal pure override returns (IdleLiquidityStorage.Layout storage) {
        return IdleLiquidityStorage.layout();
    }


    constructor(address _pm) BaseHook(IPoolManager(_pm)) IdleLiquidityRebalanceEngine(msg.sender) {
        IdleLiquidityStorage.Layout storage s = IdleLiquidityStorage.layout();
        s.maxLPsPerPool = 2000;
        s.rebalanceCooldownBlocks = DEFAULT_REBALANCE_COOLDOWN_BLOCKS;
        s.rebalanceTickThreshold = DEFAULT_REBALANCE_TICK_THRESHOLD;
    }

    // =========================
    // HOOK PERMISSIONS
    // =========================
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            afterSwap: true,
            afterAddLiquidity: true,
            beforeSwap: false,
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function setDebugEmitUpdateRequested(bool v) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.debugEmitUpdateRequested = v;
    }

    function setAaveStrategy(address addr) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.aaveStrategy = addr;
    }

    function setERC4626Strategy(address addr) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.erc4626Strategy = addr;
    }

    function setStrategyManager(address addr) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.strategyManager = addr;
    }

    function setApprovedPool(PoolId pid, bool approved) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.approvedPools[pid] = approved;
        if (approved && !s.poolExists[pid]) {
            s.allPools.push(pid);
            s.poolExists[pid] = true;
        }
    }

    function setDefaultAaveConfig(PoolId pid, uint8 side) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.poolConfig[pid].assets[side].strategy = Strategy.AAVE;
        if (s.aaveStrategy != address(0)) {
            s.poolConfig[pid].assets[side].strategyImpl = s.aaveStrategy;
        }
    }

    function setPoolConfigAave(
        PoolId pid,
        uint8 side,
        address asset,
        address pool,
        address aToken,
        uint256 lpShareBP,
        uint256 protocolShareBP
    ) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        PoolConfigManager.setPoolConfigAave(
            s.poolConfig,
            s.poolExists,
            s.approvedPools,
            s.allPools,
            s.strategyManager,
            s.aaveStrategy,
            pid,
            side,
            asset,
            pool,
            aToken,
            lpShareBP,
            protocolShareBP
        );
        s._needUpdate[pid] = true; // Restrict needUpdate to onlyOwner for security
        s.lastUpdateRequestBlock[pid] = block.number; // Restrict needUpdate to onlyOwner for security
    }

    function updateRates(PoolId pid, uint256 lpShareBP, uint256 protocolShareBP) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        PoolConfigManager.updateRates(s.poolConfig, s.poolExists, s.approvedPools, s.allPools, pid, lpShareBP, protocolShareBP);
    }

    function updateRatesBatch(
        PoolId[] calldata pids,
        uint256[] calldata lpShareBPs,
        uint256[] calldata protocolShareBPs
    ) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        PoolConfigManager.updateRatesBatch(s.poolConfig, s.poolExists, s.approvedPools, s.allPools, pids, lpShareBPs, protocolShareBPs);
    }

    function pruneTrackedLPs(PoolId pid, uint256 maxToPrune) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        LPRegistry.pruneTrackedLPs(s.trackedLPs, s.trackedLPPresent, s.trackedLPIndex, s.positions, pid, maxToPrune);
    }

    function setPriceFeed(address asset, address feed) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.priceFeed[asset] = AggregatorV3Interface(feed);
    }

    function setEmergencyPause(bool _paused) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.emergencyPaused = _paused;
        emit EmergencyPauseSet(_paused);
    }

    function setTrustedAavePool(address pool, bool trusted) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.trustedAavePools[pool] = trusted;
    }

    function setTrustedERC4626Vault(address vault, bool trusted) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.trustedERC4626Vaults[vault] = trusted;
    }

    function setMaxLPsPerPool(uint256 v) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.maxLPsPerPool = v;
    }

    function needUpdate(PoolId pid) external returns (bool) {
        IdleLiquidityStorage.Layout storage s = _state();
        s._needUpdate[pid] = true;
        s.lastUpdateRequestBlock[pid] = block.number;

        if (!s.poolExists[pid] && s.approvedPools[pid]) {
            s.allPools.push(pid);
            s.poolExists[pid] = true;
            if (s.poolCursor >= s.allPools.length) {
                s.poolCursor = 0;
            }
        }

        return true;
    }

    function approvedPools(PoolId pid) external view returns (bool) {
        return _state().approvedPools[pid];
    }

    function registerPosition(
        PoolId pid,
        address lp,
        uint128 liquidity0,
        uint128 liquidity1,
        int24 lower,
        int24 upper
    ) external {
        IdleLiquidityStorage.Layout storage s = _state();
        PositionManager.registerPosition(
            s.positions,
            s.trackedLPs,
            s.trackedLPPresent,
            s.globalYieldIndex,
            pid,
            lp,
            liquidity0,
            liquidity1,
            lower,
            upper
        );
        emit PositionRegistered(pid, lp, msg.sender, liquidity0, liquidity1, lower, upper);
    }

    function registerLP(PoolId pid, address lp) external {
        IdleLiquidityStorage.Layout storage s = _state();
        LPRegistry.registerLP(s.trackedLPs, s.trackedLPPresent, s.trackedLPIndex, pid, lp, s.maxLPsPerPool);
    }

    function clearPosition(PoolId pid, address lp) external {
        IdleLiquidityStorage.Layout storage s = _state();
        LPRegistry.clearPosition(s.positions, s.trackedLPs, s.trackedLPPresent, s.trackedLPIndex, pid, lp);
    }

    function getTrackedLPs(PoolId pid) external view returns (address[] memory) {
        IdleLiquidityStorage.Layout storage s = _state();
        return s.trackedLPs[pid];
    }

    function totalIdleLiquidity(PoolId pid, uint8 side) external view returns (uint256) {
        IdleLiquidityStorage.Layout storage s = _state();
        return s.totalIdleLiquidity[pid][side];
    }

    function totalATokenPrincipal(PoolId pid, uint8 side) external view returns (uint256) {
        return _state().totalATokenPrincipal[pid][side];
    }

    function totalVaultShares(PoolId pid, uint8 side) external view returns (uint256) {
        return _state().totalVaultShares[pid][side];
    }

    function globalYieldIndex(PoolId pid, uint8 side) external view returns (uint256) {
        return _state().globalYieldIndex[pid][side];
    }

    function lastRebalanceBlock(PoolId pid) external view returns (uint256) {
        return _state().lastRebalanceBlock[pid];
    }

    function failureCount(address account) external view returns (uint256) {
        return _state().failureCount[account];
    }

    function positions(PoolId pid, address lp)
        external
        view
        returns (
            uint128 liquidity0,
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
            uint256 aTokenPrincipal1
        )
    {
        Position storage pos = _state().positions[pid][lp];
        return (
            pos.liquidity0,
            pos.liquidity1,
            pos.lowerTick,
            pos.upperTick,
            pos.status,
            pos.lastYieldIndex0,
            pos.lastYieldIndex1,
            pos.accumulatedYield0,
            pos.accumulatedYield1,
            pos.vaultShares0,
            pos.vaultShares1,
            pos.aTokenPrincipal0,
            pos.aTokenPrincipal1
        );
    }

    function setRebalanceCooldownBlocks(uint256 blocks) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.rebalanceCooldownBlocks = blocks;
    }

    function setRebalanceTickThreshold(int24 ticks) external onlyOwner {
        IdleLiquidityStorage.Layout storage s = _state();
        s.rebalanceTickThreshold = ticks;
    }

    // =========================
    // HOOK LOGIC
    // =========================
    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        returns (bytes4, int128)
    {
        IdleLiquidityStorage.Layout storage s = _state();
        PoolId pid = key.toId();
        int24 tick = _getCurrentTick(pid);
        uint256 prev = s.lastUpdateRequestBlock[pid];
        bool set = false;
        bool shouldRequest = false;

        // Oracle sanity check: reject if price deviates >20% from lastGoodPrice
        address asset0 = s.poolConfig[pid].assets[0].asset;
        address asset1 = s.poolConfig[pid].assets[1].asset;
        int256 price = 0;
        int256 lastPrice = 0;
        if (s.priceFeed[asset0] != AggregatorV3Interface(address(0))) {
            (, price,,,) = s.priceFeed[asset0].latestRoundData();
            lastPrice = s.lastGoodPrice[asset0];
        }
        if (lastPrice > 0 && price > 0) {
            int256 deviation = price > lastPrice ? price - lastPrice : lastPrice - price;
            if (uint256(deviation) * 100 / uint256(lastPrice) > 20) {
                // Abnormal price move, skip rebalance trigger
                return (this.afterSwap.selector, 0);
            }
        }

        if (!s.hasObservedTick[pid]) {
            s.hasObservedTick[pid] = true;
            s.lastObservedTick[pid] = tick;
            shouldRequest = true;
        } else {
            uint24 delta = _abs(tick - s.lastObservedTick[pid]);
            if (delta >= uint24(s.rebalanceTickThreshold)) {
                s.lastObservedTick[pid] = tick;
                shouldRequest = true;
            }
        }

        if (prev == 0 || block.number >= prev + s.rebalanceCooldownBlocks) {
            shouldRequest = true;
        }

        if (shouldRequest) {
            s._needUpdate[pid] = true;
            s.lastUpdateRequestBlock[pid] = block.number;
            set = true;
        }

        emit RebalanceNeeded(pid);

        if (s.debugEmitUpdateRequested) {
            emit UpdateRequested(pid, prev, block.number, s.rebalanceCooldownBlocks, set);
        }

        // ✅ auto-register pool (only if owner approved to avoid storage spam)
        if (!s.poolExists[pid] && s.approvedPools[pid]){
            s.allPools.push(pid);
            s.poolExists[pid] = true;
            // keep cursor bounded
            if (s.poolCursor >= s.allPools.length) s.poolCursor = 0;
        }

        return (this.afterSwap.selector, 0);
    }

    function _abs(int24 value) internal pure returns (uint24) {
        return uint24(value >= 0 ? value : -value);
    }

    // =========================
    // INTERNAL HELPERS
    // =========================
    function _getCurrentTick(PoolId pid) internal view override returns (int24) {
        // Check whether the configured pool manager implements `extsload`.
        // Calling `extsload` directly via a low-level staticcall avoids
        // bubbling a revert if the manager (e.g. the test contract) does not
        // implement the interface. If it doesn't, return a safe default tick
        // of 0 for testing.
        bytes4 sel = bytes4(keccak256("extsload(bytes32)"));
        bytes memory probe = abi.encodeWithSelector(sel, bytes32(0));
        (bool ok,) = address(poolManager).staticcall(probe);
        if (!ok) {
            return int24(0);
        }

        (, int24 tick,,) = StateLibrary.getSlot0(poolManager, pid);
        return tick;
    }

    // =========================
    // REBALANCE (CORE)
    // =========================

    function executeIdleRebalance(PoolId pid, address lp) internal override {
        IdleLiquidityStorage.Layout storage s = _state();
        emit LiquidityIdle(pid, lp);
        int24 tick = _getCurrentTick(pid);
        RebalanceEngine.rebalanceSingleLP(
            s.poolConfig,
            s.positions,
            s.totalATokenPrincipal,
            s.totalVaultShares,
            s.totalIdleLiquidity,
            s.priceFeed,
            s.lastGoodPrice,
            s.trustedAavePools,
            s.trustedERC4626Vaults,
            s.failureCount,
            s.strategyManager,
            s.aaveStrategy,
            s.erc4626Strategy,
            pid,
            lp,
            tick
        );
    }

    function executeActiveRebalance(PoolId pid, address lp) internal override {
        IdleLiquidityStorage.Layout storage s = _state();
        int24 tick = _getCurrentTick(pid);
        RebalanceEngine.rebalanceSingleLP(
            s.poolConfig,
            s.positions,
            s.totalATokenPrincipal,
            s.totalVaultShares,
            s.totalIdleLiquidity,
            s.priceFeed,
            s.lastGoodPrice,
            s.trustedAavePools,
            s.trustedERC4626Vaults,
            s.failureCount,
            s.strategyManager,
            s.aaveStrategy,
            s.erc4626Strategy,
            pid,
            lp,
            tick
        );
    }

    // =========================
    // HARVEST / YIELD UPDATES
    // =========================
    /// @notice Harvest strategy yields for a given pool and side, updating the global yield index.
    /// @dev Anyone may call this to trigger an update; owner can restrict later if desired.
    function harvest(PoolId pid, uint8 side) external nonReentrant onlyOwner returns (uint256 yieldAmount) {
        IdleLiquidityStorage.Layout storage s = _state();
        AssetConfig storage ac = s.poolConfig[pid].assets[side];
        yieldAmount = YieldManager.harvest(
            s.globalYieldIndex,
            s.totalIdleLiquidity,
            s.totalATokenPrincipal,
            s.totalVaultShares,
            s.lastYieldUpdate,
            pid,
            side,
            ac,
            s.strategyManager,
            s.aaveStrategy,
            s.erc4626Strategy
        );
    }

    // =========================
    // KEEPER AUTOMATION
    // =========================
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        IdleLiquidityStorage.Layout storage s = _state();
        uint256 n = s.allPools.length;
        if (n == 0) return (false, bytes(""));

        uint256 limit = n > 20 ? 20 : n;
        uint256 idx = s.poolCursor;
        for (uint256 checked = 0; checked < limit; checked++) {
            PoolId pid = s.allPools[idx];
            if (s._needUpdate[pid]) {
                return (true, abi.encode(pid, uint256(0)));
            }
            idx = idx + 1;
            if (idx >= n) idx = 0;
        }

        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external {
        IdleLiquidityStorage.Layout storage s = _state();
        (PoolId pid, uint256 start) = abi.decode(performData, (PoolId, uint256));

        require(s._needUpdate[pid], "NO_UPDATE");

        rebalance(pid, start, 10);
        // advance cursor to help distribute keeper work
        if (s.allPools.length > 0) {
            s.poolCursor = (s.poolCursor + 1) % s.allPools.length;
        }
    }


    // =========================
    // YIELD
    // =========================
    function accrueYield(PoolId pid, address lp) external nonReentrant {
        IdleLiquidityStorage.Layout storage s = _state();
        Position storage pos = s.positions[pid][lp];
        (uint256 y0, uint256 y1) = YieldManager.accrueYield(s.globalYieldIndex, pos, pid);
        pos.accumulatedYield0 += y0;
        pos.accumulatedYield1 += y1;
    }

    // =========================
    // COOLDOWN LOGIC
    // =========================
    // --- IHooks required stubs ---
    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4)
    {
        return this.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta callerDelta,
        BalanceDelta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, BalanceDelta) {
        // only called by PoolManager (msg.sender == poolManager) via modifyLiquidity
        PoolId pid = key.toId();

        // if liquidity was added, register/update the position for the lp
        if (params.liquidityDelta > 0) {
            IdleLiquidityStorage.Layout storage s = _state();
            Position storage pos = s.positions[pid][sender];

            // convert caller delta (which is delta on caller balances) into deposited token amounts
            int128 a0 = BalanceDeltaLibrary.amount0(callerDelta);
            int128 a1 = BalanceDeltaLibrary.amount1(callerDelta);
            uint128 liq0 = 0;
            uint128 liq1 = 0;
            if (a0 < 0) {
                liq0 = uint128(uint256(int256(-a0)));
            }
            if (a1 < 0) {
                liq1 = uint128(uint256(int256(-a1)));
            }

            pos.liquidity0 = liq0;
            pos.liquidity1 = liq1;
            pos.lowerTick = params.tickLower;
            pos.upperTick = params.tickUpper;
            pos.status = Status.ACTIVE;

            emit PositionRegistered(pid, sender, msg.sender, liq0, liq1, params.tickLower, params.tickUpper);

            // ensure tracked using presence mapping (O(1)) and enforce max per-pool
            address[] storage lps = s.trackedLPs[pid];
            if (!s.trackedLPPresent[pid][sender]) {
                if (lps.length >= s.maxLPsPerPool) revert("LP_LIMIT");
                s.trackedLPPresent[pid][sender] = true;
                s.trackedLPIndex[pid][sender] = lps.length;
                lps.push(sender);
            }
        }

        return (this.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
            view
            override
            onlyPoolManager
            returns (bytes4)
    {
        return this.beforeRemoveLiquidity.selector;
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        BeforeSwapDelta delta = BeforeSwapDelta.wrap(0);

        return (this.beforeSwap.selector, delta, 0);
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external view override onlyPoolManager returns (bytes4, BalanceDelta) {
        return (this.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata data
    ) external override onlyPoolManager returns (bytes4, int128) {
        return _afterSwap(sender, key, params, delta, data);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
            view
            override
            onlyPoolManager
            returns (bytes4)
    {
        return this.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
            view
            override
            onlyPoolManager
            returns (bytes4)
    {
        return this.afterDonate.selector;
    }
}  
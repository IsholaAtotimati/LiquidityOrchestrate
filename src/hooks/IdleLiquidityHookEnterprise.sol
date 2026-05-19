// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {BaseHook} from "../periphery/base/hooks/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {ChainlinkAutomation} from "../automation/ChainlinkAutomation.sol";
// Aave
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
// Chainlink aggregator interface
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
// OpenZeppelin
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyExecutor} from "../strategies/StrategyExecutor.sol";
using SafeERC20 for IERC20;
import {Address} from "../../lib/v4-core/lib/openzeppelin-contracts/contracts/utils/Address.sol";

// Chainlink (imported above)

// Types
// Use the pool manager's parameter types to match the IHooks interface exactly
// (IPoolManager exposes the ModifyLiquidityParams and SwapParams types).
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IdleLiquidityHelpers} from "../helpers/IdleLiquidityHelpers.sol";
import {OracleManager} from "../managers/OracleManager.sol";
import {YieldManager} from "../managers/YieldManager.sol";
import {StrategyManager} from "../managers/StrategyManager.sol";
import {PoolConfigManager} from "../managers/PoolConfigManager.sol";
import {LPRegistry} from "../registry/LPRegistry.sol";
import {AaveConfig} from "../config/AaveConfig.sol";
import {IdleLiquidityRebalanceEngine} from "./IdleLiquidityRebalanceEngine.sol";
import {Position, AssetConfig, Status, Strategy} from "../types/IdleLiquidityTypes.sol";
import {IAaveStrategy, IERC4626Strategy, IStrategyCommon} from "../strategies/interfaces/IStrategy.sol";

contract IdleLiquidityHookEnterprise is
    BaseHook,
    IdleLiquidityRebalanceEngine,
    ChainlinkAutomation
{
    using SafeERC20 for IERC20;
    // =========================
    // EVENTS
    // =========================
    event RebalanceAttempt(PoolId indexed pid, address indexed lp);
    event EmergencyPauseSet(bool paused);
    event PositionRegistered(PoolId indexed pid, address indexed lp, address caller, uint128 liquidity0, uint128 liquidity1, int24 lower, int24 upper);
    event ConstructorDebug(address inputPoolManager, address actualPoolManager);
    event UpdateRequested(PoolId indexed pid, uint256 lastUpdateRequestBlock, uint256 currentBlock, uint256 minInterval, bool set);
    
    // =========================
    // STATE
    // =========================
    // When enabled, emit `UpdateRequested` for debugging/observability. Disabled by default in production.
    bool public debugEmitUpdateRequested;

    // Limits to control storage growth
    uint256 public maxLPsPerPool = 2000;

    // Trusted external counterparties to reduce griefing risk
    mapping(address => bool) public trustedAavePools;
    mapping(address => bool) public trustedERC4626Vaults;

    // Strategy modules (delegatecall targets)
    // legacy single-target fields retained for compatibility
    address public aaveStrategy;
    address public erc4626Strategy;

    // central manager to map Strategy enum -> implementation address
    address public strategyManager;

    function setDebugEmitUpdateRequested(bool v) external onlyOwner {
        debugEmitUpdateRequested = v;
    }

    function setAaveStrategy(address addr) external onlyOwner {
        aaveStrategy = addr;
    }

    function setERC4626Strategy(address addr) external onlyOwner {
        erc4626Strategy = addr;
    }

    function setStrategyManager(address addr) external onlyOwner {
        strategyManager = addr;
    }

    /// @notice Owner may approve pools to be tracked. Only approved pools can be added to `allPools`.
    function setApprovedPool(PoolId pid, bool approved) external onlyOwner {
        approvedPools[pid] = approved;
        if (approved && !poolExists[pid]) {
            allPools.push(pid);
            poolExists[pid] = true;
        }
    }

    PoolId[] public allPools;
    mapping(PoolId => bool) public poolExists;
    // Only approved pools may be added to `allPools` to prevent storage spam DoS
    mapping(PoolId => bool) public approvedPools;
    // rotating cursor to help keepers paginate pools without scanning from 0
    uint256 public poolCursor;

    // `onlyPoolManager` is inherited from ImmutableState/BaseHook; do not redeclare here.

    // =========================
    // CONSTRUCTOR
    // =========================
    constructor(address _pm) BaseHook(IPoolManager(_pm)) IdleLiquidityRebalanceEngine(msg.sender) {
        emit ConstructorDebug(_pm, address(poolManager));
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

    // =========================
    // HOOK LOGIC
    // =========================
    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        returns (bytes4, int128)
    {
        PoolId pid = key.toId();
        // debounce update triggers to reduce MEV/griefing surface: only set _needUpdate
        // if a minimum number of blocks has passed since the last request for this pool.
        bool set = false;
        uint256 prev = lastUpdateRequestBlock[pid];
        if (prev == 0 || block.number >= prev + MIN_UPDATE_INTERVAL_BLOCKS) {
            _needUpdate[pid] = true;
            lastUpdateRequestBlock[pid] = block.number;
            set = true;
        }
        if (debugEmitUpdateRequested) {
            emit UpdateRequested(pid, prev, block.number, MIN_UPDATE_INTERVAL_BLOCKS, set);
        }
        // ✅ auto-register pool (only if owner approved to avoid storage spam)
        if (!poolExists[pid] && approvedPools[pid]){
            allPools.push(pid);
            poolExists[pid] = true;
            // keep cursor bounded
            if (poolCursor >= allPools.length) poolCursor = 0;
        }

        return (this.afterSwap.selector, 0);
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

    function _moveToIdle(PoolId pid, address lp) internal override {
        for (uint256 side = 0; side < 2;) {
            _moveToIdleSide(pid, lp, side);
            unchecked {
                ++side;
            }
        }
    }

    function _moveToIdleSide(PoolId pid, address lp, uint256 side) internal {
        Position storage pos = positions[pid][lp];
        AssetConfig storage ac = poolConfig[pid].assets[side];
        if (address(ac.aavePool) == address(0) && address(ac.vault) == address(0) && ac.strategyImpl == address(0)) {
            return;
        }
        require(ac.asset != address(0), "ASSET_NOT_SET");
        uint256 amount = side == 0 ? pos.liquidity0 : pos.liquidity1;
        if (amount < 1e6) {
            return;
        }
        _oracleAndMove(pid, lp, ac, side, amount);
    }
 
    function _oracleAndMove(PoolId pid, address lp, AssetConfig storage ac, uint256 side, uint256 amount) internal {
        // Fetch price via OracleManager safe getter (non-reverting)
        (bool ok, int256 price) = OracleManager.safeGetPrice(priceFeed, ac.asset);
        if (!ok || price == 0) {
            if (!ok) emit ExternalCallFailed(address(priceFeed[ac.asset]), "oracle-getprice-failed", bytes(""));
            return;
        }
        OracleManager.checkDeviation(price, lastGoodPrice[ac.asset]);
        lastGoodPrice[ac.asset] = price;
        if (address(ac.aavePool) == address(0) && address(ac.vault) == address(0) && ac.strategyImpl == address(0)) return;

        address exec = address(0);
        if (strategyManager != address(0)) exec = StrategyManager(strategyManager).executor();
        if (exec == address(0)) return;
        bytes memory ret2 = Address.functionDelegateCall(
            exec,
            abi.encodeWithSelector(
                StrategyExecutor.executeDeposit.selector,
                strategyManager,
                address(ac.aavePool),
                address(ac.aToken),
                address(ac.vault),
                ac.asset,
                ac.strategyImpl,
                aaveStrategy,
                erc4626Strategy,
                trustedAavePools[address(ac.aavePool)],
                trustedERC4626Vaults[address(ac.vault)],
                amount
            )
        );
        (bool success, uint256 retVal) = abi.decode(ret2, (bool, uint256));
        if (!success) {
            return;
        }

        if (address(ac.aavePool) != address(0)) {
            _aaveUpdateBalances(pid, lp, side, amount);
        } else if (address(ac.vault) != address(0)) {
            _erc4626UpdateBalances(pid, lp, side, retVal);
        }
    }

    function _aaveUpdateBalances(PoolId pid, address lp, uint256 side, uint256 amount) internal {
        Position storage pos = positions[pid][lp];
        totalATokenPrincipal[pid][side] += amount;
        // update total idle liquidity accounting (underlying units)
        totalIdleLiquidity[pid][side] += amount;
        if (side == 0) {
            pos.aTokenPrincipal0 += amount;
            pos.liquidity0 = 0;
        } else {
            pos.aTokenPrincipal1 += amount;
            pos.liquidity1 = 0;
        }
    }

    // NOTE: price fetching moved to OracleManager.safeGetPrice (non-reverting); removed external wrapper.

    

    function _erc4626UpdateBalances(PoolId pid, address lp, uint256 side, uint256 shares) internal {
        AssetConfig storage ac = poolConfig[pid].assets[side];
        Position storage pos = positions[pid][lp];
        if (shares == 0) return;
        uint256 depositedAssets = 0;
        bool convertedOk = false;
        try ac.vault.convertToAssets(shares) returns (uint256 assets) {
            depositedAssets = assets;
            convertedOk = true;
        } catch (bytes memory reason) {
            convertedOk = false;
            failureCount[address(ac.vault)]++;
            emit ExternalCallFailed(address(ac.vault), "convertToAssets-failed", reason);
        }
        // if conversion to assets failed, mark position as FAILED and do not update totals to avoid accounting drift
        if (!convertedOk) {
            pos.status = Status.FAILED;
            return;
        }
        // Prefer shares as canonical accounting unit; update both shares and idle assets when conversion succeeded
        totalVaultShares[pid][side] += shares;
        totalIdleLiquidity[pid][side] += depositedAssets;
        if (side == 0) {
            pos.vaultShares0 += shares;
            pos.liquidity0 = 0;
        } else {
            pos.vaultShares1 += shares;
            pos.liquidity1 = 0;
        }
    }

    function _moveToActive(PoolId pid, address lp) internal override {
        for (uint256 side = 0; side < 2;) {
            AssetConfig storage ac = poolConfig[pid].assets[side];
            if (!(address(ac.aavePool) == address(0) && address(ac.vault) == address(0) && ac.strategyImpl == address(0))) {
                uint256 principalOrShares = 0;
                if (address(ac.aToken) != address(0)) {
                    principalOrShares = side == 0 ? positions[pid][lp].aTokenPrincipal0 : positions[pid][lp].aTokenPrincipal1;
                } else if (address(ac.vault) != address(0)) {
                    principalOrShares = side == 0 ? positions[pid][lp].vaultShares0 : positions[pid][lp].vaultShares1;
                }

                address exec = address(0);
                if (strategyManager != address(0)) exec = StrategyManager(strategyManager).executor();
                if (exec == address(0)) {
                    if (address(ac.aavePool) != address(0)) failureCount[address(ac.aavePool)]++;
                    if (address(ac.vault) != address(0)) failureCount[address(ac.vault)]++;
                    emit ExternalCallFailed(lp, "strategy-withdraw-failed", bytes(""));
                } else {
                    Address.functionDelegateCall(
                        exec,
                        abi.encodeWithSelector(
                            StrategyExecutor.executeWithdraw.selector,
                            strategyManager,
                            address(ac.aavePool),
                            address(ac.aToken),
                            address(ac.vault),
                            ac.asset,
                            ac.strategyImpl,
                            aaveStrategy,
                            erc4626Strategy,
                            trustedAavePools[address(ac.aavePool)],
                            trustedERC4626Vaults[address(ac.vault)],
                            principalOrShares
                        )
                    );
                }
            }
            unchecked {
                ++side;
            }
        }
    }

    // Test helper: allow the pool manager to register a position for an LP (used by MockPoolManager in tests)
    function registerPosition(
        PoolId pid,
        address lp,
        uint128 liquidity0,
        uint128 liquidity1,
        int24 lower,
        int24 upper
    ) external onlyPoolManager {
        Position storage pos = positions[pid][lp];
        // emit lightweight trace so tests can verify this helper was executed
        emit PositionRegistered(pid, lp, msg.sender, liquidity0, liquidity1, lower, upper);
        pos.liquidity0 = liquidity0;
        pos.liquidity1 = liquidity1;
        pos.lowerTick = lower;
        pos.upperTick = upper;
        pos.status = Status.ACTIVE;

        LPRegistry.registerLP(trackedLPs, trackedLPPresent, trackedLPIndex, pid, lp, maxLPsPerPool);
    }

    // Test helper: allow the pool manager to add an LP to tracked list
    function registerLP(PoolId pid, address lp) external onlyPoolManager {
        LPRegistry.registerLP(trackedLPs, trackedLPPresent, trackedLPIndex, pid, lp, maxLPsPerPool);
    }

    // Test helper: allow the pool manager to clear a position (simulate withdraw)
    function clearPosition(PoolId pid, address lp) external onlyPoolManager {
        LPRegistry.clearPosition(positions, trackedLPs, trackedLPPresent, trackedLPIndex, pid, lp);
    }

    // Test helper: return tracked LPs for a pool (view helper for tests)
    function getTrackedLPs(PoolId pid) external view returns (address[] memory) {
        return LPRegistry.getTrackedLPs(trackedLPs, pid);
    }

    // Owner helpers for trusted lists and limits
    function setTrustedAavePool(address pool, bool trusted) external onlyOwner {
        trustedAavePools[pool] = trusted;
    }

    function setTrustedERC4626Vault(address vault, bool trusted) external onlyOwner {
        trustedERC4626Vaults[vault] = trusted;
    }

    function setMaxLPsPerPool(uint256 v) external onlyOwner {
        maxLPsPerPool = v;
    }

    function _withdrawFromAave(PoolId pid, address lp, uint256 side) internal {
        Position storage pos = positions[pid][lp];
        AssetConfig storage ac = poolConfig[pid].assets[side];
        uint256 principal = side == 0 ? pos.aTokenPrincipal0 : pos.aTokenPrincipal1;
        if (principal == 0) return;
        uint256 withdrawn = 0;
        address exec = address(0);
        if (strategyManager != address(0)) exec = StrategyManager(strategyManager).executor();
        if (exec == address(0)) {
            failureCount[address(ac.aavePool)]++;
            emit ExternalCallFailed(address(ac.aavePool), "aave-withdraw-failed", bytes(""));
        } else {
            bytes memory ret = Address.functionDelegateCall(
                exec,
                abi.encodeWithSelector(
                    StrategyExecutor.executeWithdraw.selector,
                    strategyManager,
                    address(ac.aavePool),
                    address(ac.aToken),
                    address(ac.vault),
                    ac.asset,
                    ac.strategyImpl,
                    aaveStrategy,
                    erc4626Strategy,
                    trustedAavePools[address(ac.aavePool)],
                    trustedERC4626Vaults[address(ac.vault)],
                    principal
                )
            );
            withdrawn = abi.decode(ret, (uint256));
        }
        // adjust accounting based on attempted withdrawal
        if (totalATokenPrincipal[pid][side] >= principal) {
            totalATokenPrincipal[pid][side] -= principal;
        } else {
            totalATokenPrincipal[pid][side] = 0;
        }
        // reduce accounted idle liquidity by principal withdrawn (use `withdrawn` when available)
        uint256 reduceBy = withdrawn > 0 ? withdrawn : principal;
        if (totalIdleLiquidity[pid][side] >= reduceBy){
            totalIdleLiquidity[pid][side] -= reduceBy;
        } else {
            totalIdleLiquidity[pid][side] = 0;
        }
        if (side == 0) {
            pos.aTokenPrincipal0 = 0;
        } else {
            pos.aTokenPrincipal1 = 0;
        }
    }

    function _withdrawFromERC4626(PoolId pid, address lp, uint256 side) internal {
        Position storage pos = positions[pid][lp];
        AssetConfig storage ac = poolConfig[pid].assets[side];
        uint256 shares = side == 0 ? pos.vaultShares0 : pos.vaultShares1;
        if (shares == 0) return;
        // compute underlying assets represented by these shares to adjust idle accounting
        uint256 assetsOnShares = 0;
        bool convertedOk = false;
        uint256 totalSharesBefore = totalVaultShares[pid][side];
        uint256 totalIdleBefore = totalIdleLiquidity[pid][side];
        try ac.vault.convertToAssets(shares) returns (uint256 assets) {
            assetsOnShares = assets;
            convertedOk = true;
        } catch (bytes memory reason) {
            assetsOnShares = 0;
            convertedOk = false;
            failureCount[address(ac.vault)]++;
            emit ExternalCallFailed(address(ac.vault), "convertToAssets-failed", reason);
        }
        // redeem shares (redeem expects shares, withdraw expects assets)
        address exec = address(0);
        if (strategyManager != address(0)) exec = StrategyManager(strategyManager).executor();
        if (exec == address(0)) {
            failureCount[address(ac.vault)]++;
            emit ExternalCallFailed(address(ac.vault), "vault-redeem-failed", bytes(""));
        } else {
            Address.functionDelegateCall(
                exec,
                abi.encodeWithSelector(
                    StrategyExecutor.executeWithdraw.selector,
                    strategyManager,
                    address(ac.aavePool),
                    address(ac.aToken),
                    address(ac.vault),
                    ac.asset,
                    ac.strategyImpl,
                    aaveStrategy,
                    erc4626Strategy,
                    trustedAavePools[address(ac.aavePool)],
                    trustedERC4626Vaults[address(ac.vault)],
                    shares
                )
            );
        }
        // reduce shares accounting
        if (totalVaultShares[pid][side] >= shares) {
            totalVaultShares[pid][side] -= shares;
        } else {
            totalVaultShares[pid][side] = 0;
        }
        // If convertToAssets failed, approximate underlying assets using proportional math to avoid accounting drift
        if (!convertedOk) {
            if (totalSharesBefore > 0 && totalIdleBefore > 0) {
                // assetsOnShares ~ shares * totalIdleBefore / totalSharesBefore
                assetsOnShares = (shares * totalIdleBefore) / totalSharesBefore;
            } else {
                assetsOnShares = 0;
            }
        }
        // reduce idle liquidity by underlying assets represented by the withdrawn shares
        if (assetsOnShares > 0) {
            if (totalIdleLiquidity[pid][side] >= assetsOnShares) {
                totalIdleLiquidity[pid][side] -= assetsOnShares;
            } else {
                totalIdleLiquidity[pid][side] = 0;
            }
        }
        if (side == 0) {
            pos.vaultShares0 = 0;
        } else {
            pos.vaultShares1 = 0;
        }
    }

    // =========================
    // HARVEST / YIELD UPDATES
    // =========================
    /// @notice Harvest strategy yields for a given pool and side, updating the global yield index.
    /// @dev Anyone may call this to trigger an update; owner can restrict later if desired.
    function harvest(PoolId pid, uint8 side) external nonReentrant onlyOwner returns (uint256 yieldAmount) {
        AssetConfig storage ac = poolConfig[pid].assets[side];
        yieldAmount = YieldManager.harvest(
            globalYieldIndex,
            totalIdleLiquidity,
            totalATokenPrincipal,
            totalVaultShares,
            lastYieldUpdate,
            pid,
            side,
            ac,
            strategyManager,
            aaveStrategy,
            erc4626Strategy
        );
    }

    // --- TEST HELPERS (owner-only) ---
    /// @notice Test helper to set strategy accounting for unit tests only.
    function setAccountingForTest(
        PoolId pid,
        uint8 side,
        uint256 aTokenPrincipal,
        uint256 vaultShares,
        uint256 idleLiquidity
    ) external onlyOwner {
        totalATokenPrincipal[pid][side] = aTokenPrincipal;
        totalVaultShares[pid][side] = vaultShares;
        totalIdleLiquidity[pid][side] = idleLiquidity;
    }

    /// @notice Test helper to set a position's status (for unit tests)
    function setPositionStatusForTest(PoolId pid, address lp, uint8 status) external onlyOwner {
        positions[pid][lp].status = Status(status);
    }

    /// @notice Test helper to set a position's aToken principal for a side (for unit tests)
    function setPositionATokenPrincipalForTest(PoolId pid, address lp, uint8 side, uint256 amount) external onlyOwner {
        if (side == 0) {
            positions[pid][lp].aTokenPrincipal0 = amount;
        } else {
            positions[pid][lp].aTokenPrincipal1 = amount;
        }
    }

    // =========================
    // KEEPER AUTOMATION
    // =========================
    function _checkUpkeep(bytes calldata) internal view override returns (bool upkeepNeeded, bytes memory performData) {
        uint256 n = allPools.length;
        if (n == 0) return (false, bytes(""));

        uint256 limit = n > 20 ? 20 : n;
        uint256 idx = poolCursor;
        for (uint256 checked = 0; checked < limit; checked++) {
            PoolId pid = allPools[idx];
            if (_needUpdate[pid]) {
                return (true, abi.encode(pid, uint256(0)));
            }
            idx = idx + 1;
            if (idx >= n) idx = 0;
        }

        return (false, bytes(""));
    }

    function _performUpkeep(bytes calldata performData) internal override {
        (PoolId pid, uint256 start) = abi.decode(performData, (PoolId, uint256));

        require(_needUpdate[pid], "NO_UPDATE");

        rebalance(pid, start, 10);
        // advance cursor to help distribute keeper work
        if (allPools.length > 0) {
            poolCursor = (poolCursor + 1) % allPools.length;
        }
    }

    // External helper used in tests to mark a pool as needing an update.
    // In production, `_needUpdate` is set by `_afterSwap` when swaps occur.
    function needUpdate(PoolId pid) external returns (bool) {
        // Allow owner or poolManager to mark pools for update to support admin and test flows
        require(msg.sender == owner() || msg.sender == address(poolManager), "ONLY_PM_OR_OWNER");
        if (lastUpdateRequestBlock[pid] == 0 || block.number >= lastUpdateRequestBlock[pid] + MIN_UPDATE_INTERVAL_BLOCKS) {
            _needUpdate[pid] = true;
            lastUpdateRequestBlock[pid] = block.number;
        }
        return _needUpdate[pid];
    }

    // =========================
    // ADMIN CONFIG
    // =========================
    function setDefaultAaveConfig(PoolId pid, uint8 side) external onlyOwner {
        poolConfig[pid].assets[side].aavePool = IPool(AaveConfig.POOL);
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
        PoolConfigManager.setPoolConfigAave(
            poolConfig,
            poolExists,
            approvedPools,
            allPools,
            strategyManager,
            aaveStrategy,
            pid,
            side,
            asset,
            pool,
            aToken,
            lpShareBP,
            protocolShareBP
        );
    }

    // Selective variant: `flags` bitmask controls which fields to update.
    // bit 0 (1): update asset/pool/aToken/strategy/vault
    // bit 1 (2): update lpShareBP
    // bit 2 (4): update protocolShareBP
    function setPoolConfigAaveSelective(
        PoolId pid,
        uint8 side,
        address asset,
        address pool,
        address aToken,
        uint256 lpShareBP,
        uint256 protocolShareBP,
        uint8 flags
    ) external onlyOwner {
        PoolConfigManager.setPoolConfigAaveSelective(
            poolConfig,
            poolExists,
            approvedPools,
            allPools,
            strategyManager,
            aaveStrategy,
            pid,
            side,
            asset,
            pool,
            aToken,
            lpShareBP,
            protocolShareBP,
            flags
        );
    }

    // Lower-risk helper to update only the BP rates (writes only two slots).
    function updateRates(PoolId pid, uint256 lpShareBP, uint256 protocolShareBP) external onlyOwner {
        PoolConfigManager.updateRates(
            poolConfig,
            poolExists,
            approvedPools,
            allPools,
            pid,
            lpShareBP,
            protocolShareBP
        );
    }

    // Batch update helper: update rates for multiple pools in one tx.
    function updateRatesBatch(
        PoolId[] calldata pids,
        uint256[] calldata lpShareBPs,
        uint256[] calldata protocolShareBPs
    ) external onlyOwner {
        PoolConfigManager.updateRatesBatch(
            poolConfig,
            poolExists,
            approvedPools,
            allPools,
            pids,
            lpShareBPs,
            protocolShareBPs
        );
    }

    // Owner helper: prune tracked LP list by removing empty/cleared positions.
    // This is a manual, bounded operation to avoid expensive loops in production.
    function pruneTrackedLPs(PoolId pid, uint256 maxToPrune) external onlyOwner {
        LPRegistry.pruneTrackedLPs(trackedLPs, trackedLPPresent, trackedLPIndex, positions, pid, maxToPrune);
    }

    // =========================
    function setPriceFeed(address asset, address feed) external onlyOwner {
        priceFeed[asset] = AggregatorV3Interface(feed);
    }

    // EMERGENCY CONTROL
    // =========================
    function setEmergencyPause(bool _paused) external onlyOwner {
        emergencyPaused = _paused;
        emit EmergencyPauseSet(_paused);
    }

    // =========================
    // YIELD
    // =========================
    function accrueYield(PoolId pid, address lp) external nonReentrant {
        Position storage pos = positions[pid][lp];
        (uint256 y0, uint256 y1) = YieldManager.accrueYield(globalYieldIndex, pos, pid);
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
            Position storage pos = positions[pid][sender];

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
            address[] storage lps = trackedLPs[pid];
            if (!trackedLPPresent[pid][sender]) {
                if (lps.length >= maxLPsPerPool) revert("LP_LIMIT");
                trackedLPPresent[pid][sender] = true;
                trackedLPIndex[pid][sender] = lps.length;
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
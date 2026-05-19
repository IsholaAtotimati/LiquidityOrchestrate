// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Position, PoolConfig, Status, AssetConfig} from "../types/IdleLiquidityTypes.sol";
import {IdleLiquidityHelpers} from "../helpers/IdleLiquidityHelpers.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {OracleManager} from "../managers/OracleManager.sol";
import {StrategyExecutor} from "../strategies/StrategyExecutor.sol";
import {StrategyManager} from "../managers/StrategyManager.sol";
import {Address} from "../../lib/v4-core/lib/openzeppelin-contracts/contracts/utils/Address.sol";

interface IRebalanceHook {
    function rebalanceSingleLPExternal(PoolId pid, address lp, int24 tick) external;
}

library RebalanceEngine {
    uint256 internal constant MIN_GAS_LEFT = 120000;
    uint256 internal constant DUST_THRESHOLD = 1e6;

    event ExternalCallFailed(address indexed target, string reason, bytes data);
    event ReenterReady(PoolId indexed pid, address indexed lp);

    function rebalance(
        mapping(PoolId => PoolConfig) storage poolConfig,
        mapping(PoolId => mapping(address => Position)) storage positions,
        mapping(PoolId => address[]) storage trackedLPs,
        mapping(PoolId => bool) storage needUpdate,
        mapping(PoolId => uint256) storage lastRebalanceBlock,
        mapping(address => uint256) storage failureCount,
        PoolId pid,
        uint256 start,
        uint256 maxBatch,
        int24 tick,
        address hook
    ) internal {
        address[] storage lps = trackedLPs[pid];
        uint256 len = lps.length;
        require(len > 0, "NO_LPS");
        require(maxBatch > 0 && maxBatch <= 50, "INVALID_BATCH");

        uint256 end = start + maxBatch > len ? len : start + maxBatch;
        for (uint256 i = start; i < end && i < lps.length; i++) {
            address lp = lps[i];
            if (gasleft() < MIN_GAS_LEFT) {
                break;
            }
            try IRebalanceHook(hook).rebalanceSingleLPExternal(pid, lp, tick) {
            } catch (bytes memory reason) {
                failureCount[lp] += 1;
                emit ExternalCallFailed(lp, "rebalance-single-failed", reason);
            }
        }

        if (end == len) {
            needUpdate[pid] = false;
        }
        lastRebalanceBlock[pid] = block.number;
    }

    function prepareReenterBatch(
        mapping(PoolId => address[]) storage trackedLPs,
        mapping(PoolId => mapping(address => Position)) storage positions,
        PoolId pid,
        uint256 start,
        uint256 maxBatch,
        int24 tick,
        address hook,
        mapping(address => uint256) storage failureCount
    ) internal {
        address[] storage lps = trackedLPs[pid];
        uint256 len = lps.length;
        require(len > 0, "NO_LPS");

        uint256 end = start + maxBatch > len ? len : start + maxBatch;
        for (uint256 i = start; i < end && i < lps.length; i++) {
            address lp = lps[i];
            Position storage pos = positions[pid][lp];
            if (pos.status != Status.IDLE) continue;

            try IRebalanceHook(hook).rebalanceSingleLPExternal(pid, lp, tick) {
                emit ReenterReady(pid, lp);
            } catch (bytes memory reason) {
                failureCount[lp] += 1;
                emit ExternalCallFailed(lp, "reenter-withdraw-failed", reason);
            }
        }
    }

    function rebalanceSingleLP(
        mapping(PoolId => PoolConfig) storage poolConfig,
        mapping(PoolId => mapping(address => Position)) storage positions,
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(PoolId => uint256[2]) storage totalIdleLiquidity,
        mapping(address => AggregatorV3Interface) storage priceFeed,
        mapping(address => int256) storage lastGoodPrice,
        mapping(address => bool) storage trustedAavePools,
        mapping(address => bool) storage trustedERC4626Vaults,
        mapping(address => uint256) storage failureCount,
        address strategyManager,
        address aaveStrategy,
        address erc4626Strategy,
        PoolId pid,
        address lp,
        int24 tick
    ) internal {
        Position storage pos = positions[pid][lp];
        PoolConfig storage config = poolConfig[pid];

        bool outOfRange = IdleLiquidityHelpers.isOutOfRange(tick, pos.lowerTick, pos.upperTick);
        if (outOfRange && pos.status == Status.ACTIVE) {
            _moveToIdle(
                totalATokenPrincipal,
                totalVaultShares,
                totalIdleLiquidity,
                priceFeed,
                lastGoodPrice,
                trustedAavePools,
                trustedERC4626Vaults,
                failureCount,
                strategyManager,
                aaveStrategy,
                erc4626Strategy,
                pid,
                pos,
                config
            );
            pos.status = Status.IDLE;
        } else if (!outOfRange && pos.status == Status.IDLE) {
            _moveToActive(
                totalATokenPrincipal,
                totalVaultShares,
                trustedAavePools,
                trustedERC4626Vaults,
                failureCount,
                strategyManager,
                aaveStrategy,
                erc4626Strategy,
                pid,
                pos,
                config
            );
            pos.status = Status.ACTIVE;
        }
    }

    function _moveToIdle(
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(PoolId => uint256[2]) storage totalIdleLiquidity,
        mapping(address => AggregatorV3Interface) storage priceFeed,
        mapping(address => int256) storage lastGoodPrice,
        mapping(address => bool) storage trustedAavePools,
        mapping(address => bool) storage trustedERC4626Vaults,
        mapping(address => uint256) storage failureCount,
        address strategyManager,
        address aaveStrategy,
        address erc4626Strategy,
        PoolId pid,
        Position storage pos,
        PoolConfig storage config
    ) private {
        for (uint256 side = 0; side < 2; ) {
            _moveToIdleSide(
                totalATokenPrincipal,
                totalVaultShares,
                totalIdleLiquidity,
                priceFeed,
                lastGoodPrice,
                trustedAavePools,
                trustedERC4626Vaults,
                failureCount,
                strategyManager,
                aaveStrategy,
                erc4626Strategy,
                pid,
                pos,
                config.assets[side],
                side
            );
            unchecked { ++side; }
        }
    }

    function _moveToIdleSide(
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(PoolId => uint256[2]) storage totalIdleLiquidity,
        mapping(address => AggregatorV3Interface) storage priceFeed,
        mapping(address => int256) storage lastGoodPrice,
        mapping(address => bool) storage trustedAavePools,
        mapping(address => bool) storage trustedERC4626Vaults,
        mapping(address => uint256) storage failureCount,
        address strategyManager,
        address aaveStrategy,
        address erc4626Strategy,
        PoolId pid,
        Position storage pos,
        AssetConfig storage ac,
        uint256 side
    ) private {
        if (address(ac.aavePool) == address(0) && address(ac.vault) == address(0) && ac.strategyImpl == address(0)) {
            return;
        }
        require(ac.asset != address(0), "ASSET_NOT_SET");
        uint256 amount = side == 0 ? pos.liquidity0 : pos.liquidity1;
        if (amount < DUST_THRESHOLD) {
            return;
        }
        _oracleAndMove(
            totalATokenPrincipal,
            totalVaultShares,
            totalIdleLiquidity,
            priceFeed,
            lastGoodPrice,
            trustedAavePools,
            trustedERC4626Vaults,
            failureCount,
            strategyManager,
            aaveStrategy,
            erc4626Strategy,
            pid,
            pos,
            ac,
            side,
            amount
        );
    }

    function _oracleAndMove(
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(PoolId => uint256[2]) storage totalIdleLiquidity,
        mapping(address => AggregatorV3Interface) storage priceFeed,
        mapping(address => int256) storage lastGoodPrice,
        mapping(address => bool) storage trustedAavePools,
        mapping(address => bool) storage trustedERC4626Vaults,
        mapping(address => uint256) storage failureCount,
        address strategyManager,
        address aaveStrategy,
        address erc4626Strategy,
        PoolId pid,
        Position storage pos,
        AssetConfig storage ac,
        uint256 side,
        uint256 amount
    ) private {
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

        uint256 retVal = abi.decode(ret2, (uint256));
        if (address(ac.aavePool) != address(0)) {
            _aaveUpdateBalances(pid, pos, side, amount, totalATokenPrincipal, totalIdleLiquidity);
        } else if (address(ac.vault) != address(0)) {
            _erc4626UpdateBalances(pid, pos, side, retVal, totalVaultShares, totalIdleLiquidity, failureCount, ac);
        }
    }

    function _aaveUpdateBalances(
        PoolId pid,
        Position storage pos,
        uint256 side,
        uint256 amount,
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalIdleLiquidity
    ) private {
        totalATokenPrincipal[pid][side] += amount;
        totalIdleLiquidity[pid][side] += amount;
        if (side == 0) {
            pos.aTokenPrincipal0 += amount;
            pos.liquidity0 = 0;
        } else {
            pos.aTokenPrincipal1 += amount;
            pos.liquidity1 = 0;
        }
    }

    function _erc4626UpdateBalances(
        PoolId pid,
        Position storage pos,
        uint256 side,
        uint256 shares,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(PoolId => uint256[2]) storage totalIdleLiquidity,
        mapping(address => uint256) storage failureCount,
        AssetConfig storage ac
    ) private {
        if (shares == 0) return;

        bool convertedOk = false;
        uint256 depositedAssets = 0;
        try ac.vault.convertToAssets(shares) returns (uint256 assets) {
            depositedAssets = assets;
            convertedOk = true;
        } catch (bytes memory reason) {
            convertedOk = false;
            failureCount[address(ac.vault)]++;
            emit ExternalCallFailed(address(ac.vault), "convertToAssets-failed", reason);
        }
        if (!convertedOk) {
            pos.status = Status.FAILED;
            return;
        }

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

    function _moveToActive(
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(address => bool) storage trustedAavePools,
        mapping(address => bool) storage trustedERC4626Vaults,
        mapping(address => uint256) storage failureCount,
        address strategyManager,
        address aaveStrategy,
        address erc4626Strategy,
        PoolId pid,
        Position storage pos,
        PoolConfig storage config
    ) private {
        for (uint256 side = 0; side < 2; ) {
            AssetConfig storage ac = config.assets[side];
            if (!(address(ac.aavePool) == address(0) && address(ac.vault) == address(0) && ac.strategyImpl == address(0))) {
                uint256 principalOrShares = 0;
                if (address(ac.aToken) != address(0)) {
                    principalOrShares = side == 0 ? pos.aTokenPrincipal0 : pos.aTokenPrincipal1;
                } else if (address(ac.vault) != address(0)) {
                    principalOrShares = side == 0 ? pos.vaultShares0 : pos.vaultShares1;
                }

                address exec = address(0);
                if (strategyManager != address(0)) exec = StrategyManager(strategyManager).executor();
                if (exec == address(0)) {
                    if (address(ac.aavePool) != address(0)) failureCount[address(ac.aavePool)]++;
                    if (address(ac.vault) != address(0)) failureCount[address(ac.vault)]++;
                    emit ExternalCallFailed(address(0), "strategy-withdraw-failed", bytes(""));
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
            unchecked { ++side; }
        }
    }
}

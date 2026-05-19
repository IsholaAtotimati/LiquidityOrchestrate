// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Position, PoolConfig, Status, Strategy, AssetConfig} from "../types/IdleLiquidityTypes.sol";

import {IdleLiquidityHelpers} from "../helpers/IdleLiquidityHelpers.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {OracleManager} from "../managers/OracleManager.sol";

library RebalanceManager {
    using SafeERC20 for IERC20;

    uint256 internal constant DUST_THRESHOLD = 1e6;

    // =========================
    // MAIN ENTRY
    // =========================
    function rebalanceSingleLP(
        mapping(PoolId => PoolConfig) storage poolConfig,
        mapping(PoolId => mapping(address => Position)) storage positions,
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(address => AggregatorV3Interface) storage priceFeed,
        mapping(address => int256) storage lastGoodPrice,
        PoolId pid,
        address lp,
        int24 tick
    ) internal {
        Position storage pos = positions[pid][lp];
        PoolConfig storage config = poolConfig[pid];

        bool outOfRange = IdleLiquidityHelpers.isOutOfRange(
            tick,
            pos.lowerTick,
            pos.upperTick
        );

        if (outOfRange && pos.status == Status.ACTIVE) {
            _moveToIdle(
                positions,
                totalATokenPrincipal,
                totalVaultShares,
                priceFeed,
                lastGoodPrice,
                pid,
                pos,
                config
            );
            pos.status = Status.IDLE;
        } else if (!outOfRange && pos.status == Status.IDLE) {
            _moveToActive(
                positions,
                totalATokenPrincipal,
                totalVaultShares,
                pid,
                pos,
                config
            );
            pos.status = Status.ACTIVE;
        }
    }

    function _moveToIdle(
        mapping(PoolId => mapping(address => Position)) storage,
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(address => AggregatorV3Interface) storage priceFeed,
        mapping(address => int256) storage lastGoodPrice,
        PoolId pid,
        Position storage pos,
        PoolConfig storage config
    ) internal {
        for (uint256 side = 0; side < 2; ) {
            _handleMoveToIdleForAsset(
                totalATokenPrincipal,
                totalVaultShares,
                priceFeed,
                lastGoodPrice,
                pid,
                pos,
                config.assets[side],
                side
            );
            unchecked { ++side; }
        }
    }

    function _handleMoveToIdleForAsset(
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(address => AggregatorV3Interface) storage priceFeed,
        mapping(address => int256) storage lastGoodPrice,
        PoolId pid,
        Position storage pos,
        AssetConfig storage ac,
        uint256 side
    ) internal {
        if (!_isAssetActive(ac)) {
            return;
        }
        uint256 amount = _getAssetAmount(pos, side);
        if (!_isAmountSufficient(amount)) {
            return;
        }
        _updateAssetPrice(priceFeed, lastGoodPrice, ac);
        if (ac.strategy == Strategy.AAVE) {
            _moveToAave(
                totalATokenPrincipal,
                pid,
                pos,
                ac,
                side,
                amount
            );
        } else if (ac.strategy == Strategy.ERC4626) {
            _moveToERC4626(
                totalVaultShares,
                pid,
                pos,
                ac,
                side,
                amount
            );
        }
    }

    function _isAssetActive(AssetConfig storage ac) private view returns (bool) {
        return ac.strategy != Strategy.NONE && ac.asset != address(0);
    }

    function _getAssetAmount(Position storage pos, uint256 side) private view returns (uint256) {
        return side == 0 ? pos.liquidity0 : pos.liquidity1;
    }

    function _isAmountSufficient(uint256 amount) private pure returns (bool) {
        return amount >= DUST_THRESHOLD;
    }

    function _updateAssetPrice(
        mapping(address => AggregatorV3Interface) storage priceFeed,
        mapping(address => int256) storage lastGoodPrice,
        AssetConfig storage ac
    ) private {
        int256 price = OracleManager.getSafePrice(priceFeed, ac.asset);
        OracleManager.checkDeviation(price, lastGoodPrice[ac.asset]);
        lastGoodPrice[ac.asset] = price;
    }

    function _moveToAave(
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        PoolId pid,
        Position storage pos,
        AssetConfig storage ac,
        uint256 side,
        uint256 amount
    ) internal {
        IERC20 token = IERC20(ac.asset);
        require(address(ac.aavePool) != address(0), "AAVE_NOT_SET");
        require(address(ac.aToken) != address(0), "ATOKEN_NOT_SET");
        token.forceApprove(address(ac.aavePool), 0);
        token.forceApprove(address(ac.aavePool), amount);
        uint256 beforeBal = ac.aToken.balanceOf(address(this));
        ac.aavePool.supply(ac.asset, amount, address(this), 0);
        uint256 afterBal = ac.aToken.balanceOf(address(this));
        require(afterBal > beforeBal, "AAVE_DEPOSIT_FAILED");
        totalATokenPrincipal[pid][side] += amount;
        if (side == 0) {
            pos.aTokenPrincipal0 += amount;
            pos.liquidity0 = 0;
        } else {
            pos.aTokenPrincipal1 += amount;
            pos.liquidity1 = 0;
        }
    }

    function _moveToERC4626(
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        PoolId pid,
        Position storage pos,
        AssetConfig storage ac,
        uint256 side,
        uint256 amount
    ) internal {
        IERC20 token = IERC20(ac.asset);
        require(address(ac.vault) != address(0), "VAULT_NOT_SET");
        token.forceApprove(address(ac.vault), 0);
        token.forceApprove(address(ac.vault), amount);
        uint256 beforeBal = ac.vault.balanceOf(address(this));
        ac.vault.deposit(amount, address(this));
        uint256 afterBal = ac.vault.balanceOf(address(this));
        require(afterBal > beforeBal, "VAULT_DEPOSIT_FAILED");
        totalVaultShares[pid][side] += afterBal - beforeBal;
        if (side == 0) {
            pos.vaultShares0 += afterBal - beforeBal;
            pos.liquidity0 = 0;
        } else {
            pos.vaultShares1 += afterBal - beforeBal;
            pos.liquidity1 = 0;
        }
    }

    function _moveToActive(
        mapping(PoolId => mapping(address => Position)) storage,
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        PoolId pid,
        Position storage pos,
        PoolConfig storage config
    ) internal {
        for (uint256 side = 0; side < 2; ) {
            AssetConfig storage ac = config.assets[side];
            if (ac.strategy == Strategy.AAVE) {
                _withdrawFromAave(
                    totalATokenPrincipal,
                    pid,
                    pos,
                    ac,
                    side
                );
            } else if (ac.strategy == Strategy.ERC4626) {
                _withdrawFromERC4626(
                    totalVaultShares,
                    pid,
                    pos,
                    ac,
                    side
                );
            }
            unchecked { ++side; }
        }
    }

    function _withdrawFromAave(
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        PoolId pid,
        Position storage pos,
        AssetConfig storage ac,
        uint256 side
    ) internal {
        uint256 principal = side == 0 ? pos.aTokenPrincipal0 : pos.aTokenPrincipal1;
        if (principal == 0) return;
        ac.aavePool.withdraw(ac.asset, principal, address(this));
        totalATokenPrincipal[pid][side] -= principal;
        if (side == 0) {
            pos.aTokenPrincipal0 = 0;
        } else {
            pos.aTokenPrincipal1 = 0;
        }
    }

    function _withdrawFromERC4626(
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        PoolId pid,
        Position storage pos,
        AssetConfig storage ac,
        uint256 side
    ) internal {
        uint256 shares = side == 0 ? pos.vaultShares0 : pos.vaultShares1;
        if (shares == 0) return;
        ac.vault.withdraw(shares, address(this), address(this));
        totalVaultShares[pid][side] -= shares;
        if (side == 0) {
            pos.vaultShares0 = 0;
        } else {
            pos.vaultShares1 = 0;
        }
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Position, AssetConfig, Strategy} from "../types/IdleLiquidityTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategyCommon} from "../strategies/interfaces/IStrategy.sol";
import {StrategyManager} from "./StrategyManager.sol";

library YieldManager {
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant MAX_YIELD_BP = 2000; // 20% sanity cap

    function harvest(
        mapping(PoolId => uint256[2]) storage globalYieldIndex,
        mapping(PoolId => uint256[2]) storage totalIdle,
        mapping(PoolId => uint256[2]) storage totalATokenPrincipal,
        mapping(PoolId => uint256[2]) storage totalVaultShares,
        mapping(PoolId => uint256) storage lastYieldUpdate,
        PoolId pid,
        uint8 side,
        AssetConfig storage ac,
        address strategyManager,
        address aaveStrategy,
        address erc4626Strategy
    ) internal returns (uint256 yieldAmount) {
        require(side < 2, "INVALID_SIDE");

        yieldAmount = 0;
        if (address(ac.aavePool) == address(0) && address(ac.vault) == address(0) && ac.strategyImpl == address(0)) {
            return 0;
        }

        address impl = ac.strategyImpl;
        if (impl == address(0)) {
            if (aaveStrategy != address(0) && address(ac.aavePool) != address(0)) {
                impl = aaveStrategy;
            } else if (erc4626Strategy != address(0) && address(ac.vault) != address(0)) {
                impl = erc4626Strategy;
            } else if (strategyManager != address(0)) {
                if (address(ac.aavePool) != address(0)) {
                    impl = StrategyManager(strategyManager).getImplementation(Strategy.AAVE);
                } else if (address(ac.vault) != address(0)) {
                    impl = StrategyManager(strategyManager).getImplementation(Strategy.ERC4626);
                }
            }
        }
        if (impl == address(0)) {
            return 0;
        }

        bytes memory baseCtx = abi.encode(ac.aavePool, ac.aToken, ac.vault, IERC20(ac.asset), uint256(0));

        if (address(ac.aToken) != address(0)) {
            (bool okBal, bytes memory retBal) = impl.staticcall(abi.encodeWithSelector(IStrategyCommon.balanceOf.selector, address(this), baseCtx));
            if (okBal) {
                uint256 current = abi.decode(retBal, (uint256));
                uint256 principal = totalATokenPrincipal[pid][side];
                if (current > principal) {
                    yieldAmount = current - principal;
                }
            }
        } else if (address(ac.vault) != address(0)) {
            (bool okShares, bytes memory retShares) = impl.staticcall(abi.encodeWithSelector(IStrategyCommon.balanceOf.selector, address(this), baseCtx));
            if (okShares) {
                uint256 shares = abi.decode(retShares, (uint256));
                uint256 principalShares = totalVaultShares[pid][side];
                if (shares > principalShares) {
                    bytes memory ctxNow = abi.encode(ac.aavePool, ac.aToken, ac.vault, IERC20(ac.asset), shares);
                    bytes memory ctxPri = abi.encode(ac.aavePool, ac.aToken, ac.vault, IERC20(ac.asset), principalShares);
                    uint256 assetsNow = 0;
                    uint256 assetsPrincipal = 0;
                    (bool okNow, bytes memory retNow) = impl.staticcall(abi.encodeWithSelector(IStrategyCommon.convertToAssets.selector, address(this), ctxNow));
                    if (okNow) assetsNow = abi.decode(retNow, (uint256));
                    (bool okPri, bytes memory retPri) = impl.staticcall(abi.encodeWithSelector(IStrategyCommon.convertToAssets.selector, address(this), ctxPri));
                    if (okPri) assetsPrincipal = abi.decode(retPri, (uint256));
                    if (assetsNow > assetsPrincipal) {
                        yieldAmount = assetsNow - assetsPrincipal;
                    }
                }
            }
        }

        if (yieldAmount == 0) {
            return 0;
        }

        updateGlobalIndex(globalYieldIndex, totalIdle, pid, side, yieldAmount);
        lastYieldUpdate[pid] = block.timestamp;
    }

    function accrueYield(
        mapping(PoolId => uint256[2]) storage globalYieldIndex,
        Position storage pos,
        PoolId pid
    ) internal returns (uint256 y0, uint256 y1) {
        y0 = accrue(globalYieldIndex, pos, pid, 0);
        y1 = accrue(globalYieldIndex, pos, pid, 1);
    }

    /// @notice Update global yield index
    function updateGlobalIndex(
        mapping(PoolId => uint256[2]) storage globalIndex,
        mapping(PoolId => uint256[2]) storage totalIdle,
        PoolId pid,
        uint8 side,
        uint256 yieldAmount
    ) internal {
        require(side < 2, "INVALID_SIDE");

        uint256 total = totalIdle[pid][side];
        if (total == 0 || yieldAmount == 0) return;

        // sanity check: prevent extreme yield spikes
        require((yieldAmount * 10000) / total <= MAX_YIELD_BP, "YIELD_TOO_HIGH");

        globalIndex[pid][side] += (yieldAmount * PRECISION) / total;
    }

    /// @notice Accrue yield for a position
    function accrue(mapping(PoolId => uint256[2]) storage globalIndex, Position storage pos, PoolId pid, uint8 side)
        internal
        returns (uint256 accrued)
    {
        require(side < 2, "INVALID_SIDE");

        uint256 currentIndex = globalIndex[pid][side];
        uint256 lastIndex;

        uint128 liquidity;

        if (side == 0) {
            lastIndex = pos.lastYieldIndex0;
            liquidity = pos.liquidity0;
        } else {
            lastIndex = pos.lastYieldIndex1;
            liquidity = pos.liquidity1;
        }

        // no liquidity = no yield
        if (liquidity == 0) {
            _updateIndex(pos, side, currentIndex);
            return 0;
        }

        accrued = ((currentIndex - lastIndex) * liquidity) / PRECISION;
        _updateIndex(pos, side, currentIndex);
    }

    function _updateIndex(Position storage pos, uint8 side, uint256 newIndex) internal {
        if (side == 0) {
            pos.lastYieldIndex0 = newIndex;
        } else {
            pos.lastYieldIndex1 = newIndex;
        }
    }
}

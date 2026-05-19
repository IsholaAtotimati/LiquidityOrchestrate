// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {StrategyManager} from "../managers/StrategyManager.sol";
import {Strategy} from "../types/IdleLiquidityTypes.sol";
import {IStrategyCommon} from "./interfaces/IStrategy.sol";
import {Address} from "../../lib/v4-core/lib/openzeppelin-contracts/contracts/utils/Address.sol";

contract StrategyExecutor {
    // Primary entrypoints. These functions are intended to be called via
    // `delegatecall` from the Hook so that `address(this)` and storage
    // references refer to the Hook contract.

    function resolveImplementation(
        address strategyManager,
        address strategyImpl,
        address aavePool,
        address vault,
        address aaveStrategy,
        address erc4626Strategy
    ) public view returns (address) {
        if (strategyImpl != address(0)) {
            return strategyImpl;
        }
        if (aaveStrategy != address(0) && aavePool != address(0)) {
            return aaveStrategy;
        }
        if (erc4626Strategy != address(0) && vault != address(0)) {
            return erc4626Strategy;
        }
        if (strategyManager == address(0)) {
            return address(0);
        }
        if (aavePool != address(0)) {
            return StrategyManager(strategyManager).getImplementation(Strategy.AAVE);
        }
        if (vault != address(0)) {
            return StrategyManager(strategyManager).getImplementation(Strategy.ERC4626);
        }
        return address(0);
    }

    function executeDeposit(
        address strategyManager,
        address aavePool,
        address aToken,
        address vault,
        address asset,
        address strategyImpl,
        address aaveStrategy,
        address erc4626Strategy,
        bool trustedAavePool,
        bool trustedERC4626Vault,
        uint256 amount
    ) external returns (bool, uint256) {
        if (aavePool != address(0) && !trustedAavePool) {
            return (false, 0);
        }
        if (vault != address(0) && !trustedERC4626Vault) {
            return (false, 0);
        }

        address impl = resolveImplementation(strategyManager, strategyImpl, aavePool, vault, aaveStrategy, erc4626Strategy);
        if (impl != address(0)) {
            bytes memory ctx = abi.encode(
                IPool(aavePool),
                IERC20(aToken),
                IERC4626(vault),
                IERC20(asset),
                amount
            );
            bytes memory ret = Address.functionDelegateCall(impl, abi.encodeWithSelector(IStrategyCommon.deposit.selector, ctx));
            return (true, abi.decode(ret, (uint256)));
        }

        if (aavePool != address(0)) {
            IERC20(asset).approve(aavePool, amount);
            uint256 beforeBal = IERC20(aToken).balanceOf(address(this));
            try IPool(aavePool).supply(asset, amount, address(this), 0) {
            } catch {
                return (false, 0);
            }
            uint256 afterBal = IERC20(aToken).balanceOf(address(this));
            if (afterBal <= beforeBal) {
                return (false, 0);
            }
            return (true, afterBal - beforeBal);
        }

        if (vault != address(0)) {
            IERC20(asset).approve(vault, amount);
            uint256 beforeBal = IERC4626(vault).balanceOf(address(this));
            try IERC4626(vault).deposit(amount, address(this)) returns (uint256) {
            } catch {
                return (false, 0);
            }
            uint256 afterBal = IERC4626(vault).balanceOf(address(this));
            if (afterBal <= beforeBal) {
                return (false, 0);
            }
            return (true, afterBal - beforeBal);
        }

        return (false, 0);
    }

    function executeWithdraw(
        address strategyManager,
        address aavePool,
        address aToken,
        address vault,
        address asset,
        address strategyImpl,
        address aaveStrategy,
        address erc4626Strategy,
        bool trustedAavePool,
        bool trustedERC4626Vault,
        uint256 amountOrShares
    ) external returns (bool, uint256) {
        if (aavePool != address(0) && !trustedAavePool) {
            return (false, 0);
        }
        if (vault != address(0) && !trustedERC4626Vault) {
            return (false, 0);
        }

        address impl = resolveImplementation(strategyManager, strategyImpl, aavePool, vault, aaveStrategy, erc4626Strategy);
        if (impl != address(0)) {
            bytes memory ctx = abi.encode(
                IPool(aavePool),
                IERC20(aToken),
                IERC4626(vault),
                IERC20(asset),
                amountOrShares
            );
            (bool ok, bytes memory ret) = impl.delegatecall(
                abi.encodeWithSelector(IStrategyCommon.withdraw.selector, ctx)
            );
            if (!ok) {
                return (false, 0);
            }
            return (true, abi.decode(ret, (uint256)));
        }

        if (aavePool != address(0)) {
            try IPool(aavePool).withdraw(asset, amountOrShares, address(this)) returns (uint256 w) {
                return (true, w);
            } catch {
                return (false, 0);
            }
        }

        if (vault != address(0)) {
            try IERC4626(vault).redeem(amountOrShares, address(this), address(this)) {
                return (true, 0);
            } catch {
                return (false, 0);
            }
        }

        return (false, 0);
    }
}

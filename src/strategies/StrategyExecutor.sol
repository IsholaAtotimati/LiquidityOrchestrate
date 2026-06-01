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
    // Primary entrypoints. These functions are intended to be called directly
    // by the RebalanceEngine through the executor contract.

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

    function prepareDeposit(
        address hook,
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
    ) external view returns (bool, address, bytes memory) {
        if (aavePool != address(0) && !trustedAavePool) {
            return (false, address(0), bytes(""));
        }
        if (vault != address(0) && !trustedERC4626Vault) {
            return (false, address(0), bytes(""));
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
            bytes memory ret = Address.functionStaticCall(impl, abi.encodeWithSelector(IStrategyCommon.prepareDeposit.selector, hook, ctx));
            (address target, bytes memory data) = abi.decode(ret, (address, bytes));
            return (true, target, data);
        }

        return (false, address(0), bytes(""));
    }

    function prepareWithdraw(
        address hook,
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
    ) external view returns (bool, address, bytes memory) {
        if (aavePool != address(0) && !trustedAavePool) {
            return (false, address(0), bytes(""));
        }
        if (vault != address(0) && !trustedERC4626Vault) {
            return (false, address(0), bytes(""));
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
            bytes memory ret = Address.functionStaticCall(impl, abi.encodeWithSelector(IStrategyCommon.prepareWithdraw.selector, hook, ctx));
            (address target, bytes memory data) = abi.decode(ret, (address, bytes));
            return (true, target, data);
        }

        return (false, address(0), bytes(""));
    }
}

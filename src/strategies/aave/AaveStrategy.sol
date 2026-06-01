// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// Minimal internal helper: use low-level calls to perform approve when tokens
// have non-standard return behaviour. This mirrors the project's previous
// `forceApprove` usage without requiring external helpers.

contract AaveStrategy {
    event AaveWithdrawDebug(address pool, address aToken, address asset, uint256 principal, uint256 allowance, uint256 balance);

    // Strategy implementation for Aave; external calls use an explicit hook address so `address(this)` is the strategy contract.
    function depositToAave(address hook, IPool pool, IERC20 aToken, IERC20 asset, uint256 amount) internal returns (uint256) {
        require(hook != address(0), "HOOK_NOT_SET");
        require(address(pool) != address(0), "AAVE_NOT_SET");
        require(address(aToken) != address(0), "ATOKEN_NOT_SET");
        _forceApprove(asset, address(pool), 0);
        _forceApprove(asset, address(pool), amount);
        uint256 beforeBal = aToken.balanceOf(hook);
        try pool.supply(address(asset), amount, hook, 0) {
        } catch {
            revert("AAVE_SUPPLY_FAILED");
        }
        uint256 afterBal = aToken.balanceOf(hook);
        require(afterBal > beforeBal, "AAVE_DEPOSIT_FAILED");
        return afterBal - beforeBal;
    }

    function withdrawFromAave(address hook, IPool pool, IERC20 aToken, IERC20 asset, uint256 principal) internal returns (uint256) {
        if (principal == 0) return 0;
        uint256 balance = aToken.balanceOf(hook);
        emit AaveWithdrawDebug(address(pool), address(aToken), address(asset), principal, 0, balance);
        require(balance >= principal, "AAVE_ATOKEN_BALANCE_INSUFFICIENT");
        uint256 withdrawn = 0;
        try pool.withdraw(address(asset), principal, hook) returns (uint256 w) {
            withdrawn = w;
        } catch {
            (bool ok, bytes memory ret) = address(pool).call(
                abi.encodeWithSelector(IPool.withdraw.selector, address(asset), principal, hook)
            );
            if (ok && ret.length >= 32) {
                withdrawn = abi.decode(ret, (uint256));
            } else {
                revert("AAVE_WITHDRAW_FAILED");
            }
        }
        return withdrawn;
    }

    function _forceApprove(IERC20 token, address spender, uint256 amount) internal {
        // First attempt the standard high-level call. Many ERC20s implement
        // `approve` and return `bool` — prefer that path for correctness.
        bool approved = false;
        try token.approve(spender, amount) returns (bool ok) {
            approved = ok;
        } catch {
            approved = false;
        }

        if (!approved) {
            // Fallback: try a low-level call for non-standard tokens.
            (bool okLow, ) = address(token).call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
            require(okLow, "APPROVE_FAILED");
        }
    }

    // Compatibility wrappers: preserve original logic while exposing the
    // requested function names. These call the existing implementations to
    // avoid duplicating logic and to ensure behavior remains unchanged.
    function _moveToAave(IPool pool, IERC20 aToken, IERC20 asset, uint256 amount) external returns (uint256) {
        return depositToAave(address(this), pool, aToken, asset, amount);
    }

    function _withdrawFromAave(IPool pool, IERC20 aToken, IERC20 asset, uint256 principal) external returns (uint256) {
        return withdrawFromAave(address(this), pool, aToken, asset, principal);
    }

    function _aaveApproveAndSupply(IPool pool, IERC20 aToken, IERC20 asset, uint256 amount) external returns (uint256) {
        return depositToAave(address(this), pool, aToken, asset, amount);
    }

    // Generic facade for unified strategy interface
    // Unified context layout used by the Hook when calling strategies:
    // (IPool aavePool, IERC20 aToken, IERC4626 vault, IERC20 asset, uint256 amountOrShares)
    function prepareDeposit(address hook, bytes calldata ctx) external pure returns (address target, bytes memory data) {
        (IPool pool, IERC20 aToken, IERC4626 vault, IERC20 asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        target = address(pool);
        data = abi.encodeWithSelector(IPool.supply.selector, address(asset), amountOrShares, hook, 0);
    }

    function prepareWithdraw(address hook, bytes calldata ctx) external pure returns (address target, bytes memory data) {
        (IPool pool, IERC20 aToken, IERC4626 vault, IERC20 asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        target = address(pool);
        data = abi.encodeWithSelector(IPool.withdraw.selector, address(asset), amountOrShares, hook);
    }

    function balanceOf(address hook, bytes calldata ctx) external view returns (uint256) {
        (IPool _pool, IERC20 aToken, IERC4626 _vault, IERC20 _asset, uint256 _amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return aToken.balanceOf(hook);
    }

    function convertToAssets(address hook, bytes calldata ctx) external pure returns (uint256) {
        // Not applicable for Aave; return input amount as passthrough for compatibility.
        (IPool _pool, IERC20 _aToken, IERC4626 _vault, IERC20 _asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return amountOrShares;
    }
}


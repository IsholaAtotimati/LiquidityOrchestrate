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

    // Designed to be used via delegatecall from the Hook so `address(this)` refers to the Hook
    function depositToAave(IPool pool, IERC20 aToken, IERC20 asset, uint256 amount) internal returns (uint256) {
        require(address(pool) != address(0), "AAVE_NOT_SET");
        require(address(aToken) != address(0), "ATOKEN_NOT_SET");
        _forceApprove(asset, address(pool), 0);
        _forceApprove(asset, address(pool), amount);
        uint256 beforeBal = aToken.balanceOf(address(this));
        try pool.supply(address(asset), amount, address(this), 0) {
        } catch {
            revert("AAVE_SUPPLY_FAILED");
        }
        uint256 afterBal = aToken.balanceOf(address(this));
        require(afterBal > beforeBal, "AAVE_DEPOSIT_FAILED");
        return afterBal - beforeBal;
    }

    function withdrawFromAave(IPool pool, IERC20 aToken, IERC20 asset, uint256 principal) internal returns (uint256) {
        if (principal == 0) return 0;
        uint256 allowance = aToken.allowance(address(this), address(pool));
        uint256 balance = aToken.balanceOf(address(this));
        emit AaveWithdrawDebug(address(pool), address(aToken), address(asset), principal, allowance, balance);
        require(balance >= principal, "AAVE_ATOKEN_BALANCE_INSUFFICIENT");
        uint256 withdrawn = 0;
        try pool.withdraw(address(asset), principal, address(this)) returns (uint256 w) {
            withdrawn = w;
        } catch {
            (bool ok, bytes memory ret) = address(pool).call(
                abi.encodeWithSignature("withdraw(address,uint256,address)", address(asset), principal, address(this))
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
        return depositToAave(pool, aToken, asset, amount);
    }

    function _withdrawFromAave(IPool pool, IERC20 aToken, IERC20 asset, uint256 principal) external returns (uint256) {
        return withdrawFromAave(pool, aToken, asset, principal);
    }

    function _aaveApproveAndSupply(IPool pool, IERC20 aToken, IERC20 asset, uint256 amount) external returns (uint256) {
        return depositToAave(pool, aToken, asset, amount);
    }

    // Generic facade for unified strategy interface
    // Unified context layout used by the Hook when calling strategies:
    // (IPool aavePool, IERC20 aToken, IERC4626 vault, IERC20 asset, uint256 amountOrShares, bytes extra)
    function deposit(bytes calldata ctx) external returns (uint256) {
        (IPool pool, IERC20 aToken, IERC4626 vault, IERC20 asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return depositToAave(pool, aToken, asset, amountOrShares);
    }

    function withdraw(bytes calldata ctx) external returns (uint256) {
        (IPool pool, IERC20 aToken, IERC4626 vault, IERC20 asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return withdrawFromAave(pool, aToken, asset, amountOrShares);
    }

    function balanceOf(bytes calldata ctx) external view returns (uint256) {
        (IPool _pool, IERC20 aToken, IERC4626 _vault, IERC20 _asset, uint256 _amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return aToken.balanceOf(address(this));
    }

    function convertToAssets(bytes calldata ctx) external pure returns (uint256) {
        // Not applicable for Aave; return input amount as passthrough for compatibility.
        (IPool _pool, IERC20 _aToken, IERC4626 _vault, IERC20 _asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return amountOrShares;
    }
}


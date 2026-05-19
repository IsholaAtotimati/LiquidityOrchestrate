// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
// note: use internal low-level approve helper instead of relying on external `forceApprove` helper

contract ERC4626Strategy {
    // Designed to be used via delegatecall from the Hook so `address(this)` refers to the Hook
    function depositToVault(IERC4626 vault, IERC20 asset, uint256 amount) internal returns (uint256) {
        require(address(vault) != address(0), "VAULT_NOT_SET");
        _forceApprove(asset, address(vault), 0);
        _forceApprove(asset, address(vault), amount);
        uint256 beforeBal = vault.balanceOf(address(this));
        try vault.deposit(amount, address(this)) returns (uint256 s) {
            // some vaults return minted shares
        } catch {
            revert("VAULT_DEPOSIT_FAILED");
        }
        uint256 afterBal = vault.balanceOf(address(this));
        require(afterBal > beforeBal, "VAULT_DEPOSIT_FAILED");
        return afterBal - beforeBal;
    }

    function redeemFromVault(IERC4626 vault, uint256 shares) internal returns (bool) {
        if (shares == 0) return true;
        try vault.redeem(shares, address(this), address(this)) {
            return true;
        } catch {
            revert("VAULT_REDEEM_FAILED");
        }
    }

    function _forceApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool ok, ) = address(token).call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok, "APPROVE_FAILED");
    }

    // Generic facade for unified strategy interface
    // Unified context layout used by the Hook:
    // (IPool aavePool, IERC20 aToken, IERC4626 vault, IERC20 asset, uint256 amountOrShares, bytes extra)
    function deposit(bytes calldata ctx) external returns (uint256) {
        (IPool _pool, IERC20 _aToken, IERC4626 vault, IERC20 asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return depositToVault(vault, asset, amountOrShares);
    }

    function withdraw(bytes calldata ctx) external returns (uint256) {
        (IPool _pool, IERC20 _aToken, IERC4626 vault, IERC20 _asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        redeemFromVault(vault, amountOrShares);
        return 0;
    }

    function balanceOf(bytes calldata ctx) external view returns (uint256) {
        (IPool _pool, IERC20 _aToken, IERC4626 vault, IERC20 _asset, uint256 _amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return vault.balanceOf(address(this));
    }

    function convertToAssets(bytes calldata ctx) external view returns (uint256) {
        (IPool _pool, IERC20 _aToken, IERC4626 vault, IERC20 _asset, uint256 amountOrShares) = abi.decode(ctx, (IPool, IERC20, IERC4626, IERC20, uint256));
        return vault.convertToAssets(amountOrShares);
    }
}

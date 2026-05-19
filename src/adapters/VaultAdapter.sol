// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library VaultAdapter {
    function depositToVault(IERC4626 vault, IERC20 asset, uint256 amount, address receiver)
        internal
        returns (uint256 shares)
    {
        asset.approve(address(vault), amount);
        shares = vault.deposit(amount, receiver);
    }

    function withdrawFromVault(IERC4626 vault, uint256 shares, address receiver) internal returns (uint256 assets) {
        assets = vault.redeem(shares, receiver, receiver);
    }
}

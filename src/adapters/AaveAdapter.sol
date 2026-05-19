// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library AaveAdapter {
    function depositToAave(ILendingPool lendingPool, IERC20 asset, uint256 amount, address receiver) internal {
        asset.approve(address(lendingPool), amount);
        lendingPool.deposit(address(asset), amount, receiver, 0);
    }

    function withdrawFromAave(ILendingPool lendingPool, address asset, uint256 amount, address receiver)
        internal
        returns (uint256 withdrawn)
    {
        withdrawn = lendingPool.withdraw(asset, amount, receiver);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IAaveStrategy {
    /// @notice Deposit `amount` of `asset` into `pool`. Returns aToken balance increase.
    function depositToAave(IPool pool, IERC20 aToken, IERC20 asset, uint256 amount) external returns (uint256);

    /// @notice Withdraw `principal` underlying from `pool`. Returns withdrawn underlying when available.
    function withdrawFromAave(IPool pool, IERC20 aToken, IERC20 asset, uint256 principal) external returns (uint256);
}

interface IERC4626Strategy {
    /// @notice Deposit `amount` of `asset` into `vault`. Returns shares minted.
    function depositToVault(IERC4626 vault, IERC20 asset, uint256 amount) external returns (uint256);

    /// @notice Redeem `shares` from `vault`. Returns whether call succeeded (assets value should be computed by caller if needed).
    function redeemFromVault(IERC4626 vault, uint256 shares) external returns (bool); 
}

interface IStrategyCommon {
    /// @notice Prepare a deposit call from the Hook.
    function prepareDeposit(address hook, bytes calldata ctx) external view returns (address target, bytes memory data);

    /// @notice Prepare a withdraw call from the Hook.
    function prepareWithdraw(address hook, bytes calldata ctx) external view returns (address target, bytes memory data);

    /// @notice Return current protocol-specific balance for the hook address.
    function balanceOf(address hook, bytes calldata ctx) external view returns (uint256);

    /// @notice For ERC4626-like strategies: convert `shares` to underlying assets. For other strategies may return the input.
    function convertToAssets(address hook, bytes calldata ctx) external view returns (uint256);
}

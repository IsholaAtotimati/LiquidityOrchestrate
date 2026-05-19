// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC4626Vault {
    string public name = "Mock ERC4626 Vault";
    string public symbol = "mVAULT";
    uint8 public decimals = 18;
    address public assetAddress;
    uint256 public totalAssetsValue;
    mapping(address => uint256) public shareBalance;
    mapping(address => uint256) public allowance;

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    constructor(address _asset) {
        assetAddress = _asset;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[spender] = amount;
        return true;
    }

    function deposit(uint256 amount, address to) external returns (uint256) {
        require(amount > 0, "ZERO_AMOUNT");
        require(IERC20(assetAddress).transferFrom(msg.sender, address(this), amount), "TRANSFER_FAILED");
        totalAssetsValue += amount;
        shareBalance[to] += amount;
        emit Deposit(msg.sender, to, amount, amount);
        return amount;
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
        require(shareBalance[owner] >= shares, "insufficient shares");
        shareBalance[owner] -= shares;
        totalAssetsValue -= shares;
        require(IERC20(assetAddress).transfer(receiver, shares), "TRANSFER_FAILED");
        emit Withdraw(msg.sender, receiver, owner, shares, shares);
        return shares;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return shareBalance[owner];
    }

    function asset() external view returns (address) {
        return assetAddress;
    }

    function totalAssets() external view returns (uint256) {
        return totalAssetsValue;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256) {
        return redeem(assets, receiver, owner);
    }
}

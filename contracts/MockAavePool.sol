// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMockAToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
}

contract MockAavePool {
    event MockAaveWithdrawCall(address caller, address asset, uint256 amount, address to, uint256 aTokenAllowance, uint256 aTokenBalance);

    IMockAToken public aToken;

    constructor(address _aToken) {
        aToken = IMockAToken(_aToken);
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        require(IERC20(asset).transferFrom(onBehalfOf, address(this), amount), "TRANSFER_FAILED");
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        emit MockAaveWithdrawCall(msg.sender, asset, amount, to, aToken.allowance(msg.sender, address(this)), aToken.balanceOf(msg.sender));
        aToken.burnFrom(msg.sender, amount);
        require(IERC20(asset).transfer(to, amount), "TRANSFER_FAILED");
        return amount;
    }
}

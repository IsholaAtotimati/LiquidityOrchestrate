// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../ERC20.sol";

/// @notice Minimal ERC20 preset for tests exposing a `mint` helper.
contract ERC20PresetMinterPauser is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}

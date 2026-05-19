// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ImmutableState} from "../../../base/Immutable.sol";

/// @title Base Hook
/// @notice abstract contract for hook implementations
abstract contract BaseHook is IHooks, ImmutableState {
    error HookNotImplemented();

    // constructor(IPoolManager _manager) ImmutableState(_manager) {
    //     validateHookAddress(this);
    // }
    constructor(IPoolManager _poolManager) ImmutableState(_poolManager) {
        // if (block.chainid != 31337) {
        //     validateHookAddress(this);
        // }
    }

    // @notice Returns a struct of permissions to signal which hook functions are to be implemented
    /// @dev Used at deployment to validate the address correctly represents the expected permissions
    /// @return Permissions struct
    function getHookPermissions() public pure virtual returns (Hooks.Permissions memory);

    /// @notice Validates the deployed hook address agrees with the expected permissions of the hook
    /// @dev this function is virtual so that we can override it during testing,
    /// which allows us to deploy an implementation to any address
    /// and then etch the bytecode into the correct address
    function validateHookAddress(BaseHook _this) internal pure virtual {
        Hooks.validateHookPermissions(_this, getHookPermissions());
    }

    /// @inheritdoc IHooks
    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        onlyPoolManager
        returns (bytes4)
    {
        return _beforeInitialize(sender, key, sqrtPriceX96);
    }

    function _beforeInitialize(address, PoolKey calldata, uint160) internal virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    /// @inheritdoc IHooks
    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        external
        onlyPoolManager
        returns (bytes4)
    {
        return _afterInitialize(sender, key, sqrtPriceX96, tick);
    }

    function _afterInitialize(address, PoolKey calldata, uint160, int24) internal virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    // ...existing code...
}

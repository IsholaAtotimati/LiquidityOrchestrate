// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/// @notice Minimal interface for ImmutableState
interface IImmutableState {
    function poolManager() external view returns (IPoolManager);
}

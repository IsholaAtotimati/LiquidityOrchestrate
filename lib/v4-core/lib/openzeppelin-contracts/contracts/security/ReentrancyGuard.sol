// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Simple shim to re-export existing ReentrancyGuard implementation which
// lives under `contracts/utils/ReentrancyGuard.sol` in this vendor tree.
import "../utils/ReentrancyGuard.sol";

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library HookMiner {
    // Minimal shim for build/test; real implementation not needed for local tests
    function find(
        address,
        uint160,
        bytes memory,
        bytes memory
    ) internal pure returns (address, bytes32) {
        return (address(0), bytes32(0));
    }
}

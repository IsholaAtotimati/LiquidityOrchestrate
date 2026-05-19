// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract Create2Deployer {
    event Deployed(address addr, bytes32 salt);
    event Create2Revert(bytes revertData);

    function deploy(bytes memory bytecode, bytes32 salt) public returns (address addr) {
        assembly {
            let encoded_data := add(bytecode, 0x20)
            let encoded_size := mload(bytecode)
            addr := create2(0, encoded_data, encoded_size, salt)
            if iszero(addr) {
                // Copy returndata
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                // Emit event with revert data
                // log1(ptr, size, keccak256("Create2Revert(bytes)"))
                // Instead, revert with data so ethers can catch it
                revert(ptr, size)
            }
        }
        emit Deployed(addr, salt);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @notice Minimal CREATE2 deployer utility used to deterministically deploy contracts.
contract Create2Deployer {
    event Deployed(address addr, bytes32 salt);

    function deploy(bytes memory code, bytes32 salt) external returns (address addr) {
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
        }
        require(addr != address(0), "CREATE2_DEPLOY_FAILED");
        emit Deployed(addr, salt);
    }

    function call(address target, bytes calldata data) external payable returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: msg.value}(data);
        require(success, "CREATE2_CALL_FAILED");
        return result;
    }

    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer) external pure returns (address) {
        bytes32 data = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash));
        return address(uint160(uint256(data)));
    }
}

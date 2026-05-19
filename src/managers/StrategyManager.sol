// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Strategy} from "../types/IdleLiquidityTypes.sol";

contract StrategyManager {
    address public owner;

    // map Strategy enum value -> implementation address
    mapping(uint8 => address) public implementations;
    // executor contract address (contains execution logic; called via delegatecall)
    address public executor;

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    function setImplementation(Strategy s, address impl) external onlyOwner {
        implementations[uint8(s)] = impl;
    }

    function setExecutor(address exec) external onlyOwner {
        executor = exec;
    }

    function getImplementation(Strategy s) external view returns (address) {
        return implementations[uint8(s)];
    }
}

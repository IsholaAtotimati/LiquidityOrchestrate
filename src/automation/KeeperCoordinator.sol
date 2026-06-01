// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ChainlinkAutomation} from "./ChainlinkAutomation.sol";

interface IRebalanceTarget {
    function rebalance(PoolId pid, uint256 start, uint256 maxBatch) external;
}

contract KeeperCoordinator is ChainlinkAutomation, Ownable {
    event HookRebalanceTriggered(address indexed target, PoolId indexed pid, uint256 start, uint256 maxBatch);

    constructor(address owner_) Ownable(owner_) {}

    function rebalanceHook(address target, PoolId pid, uint256 start, uint256 maxBatch) external onlyOwner {
        IRebalanceTarget(target).rebalance(pid, start, maxBatch);
        emit HookRebalanceTriggered(target, pid, start, maxBatch);
    }

    function _checkUpkeep(bytes calldata) internal pure override returns (bool upkeepNeeded, bytes memory performData) {
        return (false, bytes(""));
    }

    function _performUpkeep(bytes calldata) internal override {
        // Keeper coordinator currently delegates explicit rebalance execution.
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IdleLiquidityStorage} from "../storage/IdleLiquidityStorage.sol";
import {Position, Status} from "../types/IdleLiquidityTypes.sol";
import {IdleLiquidityHelpers} from "../helpers/IdleLiquidityHelpers.sol";
import {RebalanceEngine} from "../managers/RebalanceEngine.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract IdleLiquidityRebalanceEngine is IdleLiquidityStorage, ReentrancyGuard, Ownable {
    uint256 public constant MIN_GAS_LEFT = 120000;
    uint256 public constant REBALANCE_COOLDOWN_BLOCKS = 20;

    event ReenterReady(PoolId indexed pid, address indexed lp);
    event ExternalCallFailed(address indexed target, string reason, bytes data);

    mapping(address => uint256) public failureCount;

    function _getCurrentTick(PoolId pid) internal view virtual returns (int24);
    function _moveToIdle(PoolId pid, address lp) internal virtual;
    function _moveToActive(PoolId pid, address lp) internal virtual;

    constructor(address owner_) Ownable(owner_) {}

    modifier cooldownPassed(PoolId pid) {
        require(
            lastRebalanceBlock[pid] == 0 || block.number > lastRebalanceBlock[pid] + REBALANCE_COOLDOWN_BLOCKS,
            "COOLDOWN"
        );
        _;
    }

    function rebalance(PoolId pid, uint256 start, uint256 maxBatch) public nonReentrant cooldownPassed(pid) {
        require(!emergencyPaused, "PAUSED");
        require(_needUpdate[pid], "NO_UPDATE");
        require(maxBatch > 0 && maxBatch <= 50, "INVALID_BATCH");
        require(msg.sender == owner() || msg.sender == address(this), "NOT_AUTHORIZED");

        int24 tick = _getCurrentTick(pid);

        RebalanceEngine.rebalance(
            poolConfig,
            positions,
            trackedLPs,
            _needUpdate,
            lastRebalanceBlock,
            failureCount,
            pid,
            start,
            maxBatch,
            tick,
            address(this)
        );
    }

    function _rebalanceSingleLP(PoolId pid, address lp, int24 tick) internal {
        Position storage pos = positions[pid][lp];
        bool outOfRange = IdleLiquidityHelpers.isOutOfRange(tick, pos.lowerTick, pos.upperTick);
        if (outOfRange && pos.status == Status.ACTIVE) {
            _moveToIdle(pid, lp);
            positions[pid][lp].status = Status.IDLE;
        } else if (!outOfRange && pos.status == Status.IDLE) {
            _moveToActive(pid, lp);
            positions[pid][lp].status = Status.ACTIVE;
        }
    }

    function rebalanceSingleLPExternal(PoolId pid, address lp, int24 tick) external {
        require(msg.sender == address(this) || msg.sender == owner(), "NOT_AUTHORIZED");
        _rebalanceSingleLP(pid, lp, tick);
    }

    function prepareReenterBatch(PoolId pid, uint256 start, uint256 maxBatch) external nonReentrant onlyOwner {
        int24 tick = _getCurrentTick(pid);
        RebalanceEngine.prepareReenterBatch(
            trackedLPs,
            positions,
            pid,
            start,
            maxBatch,
            tick,
            address(this),
            failureCount
        );
    }
}

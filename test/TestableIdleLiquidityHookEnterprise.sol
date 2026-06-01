// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Status} from "../src/types/IdleLiquidityTypes.sol";

contract TestableIdleLiquidityHookEnterprise is IdleLiquidityHookEnterprise {
    constructor(address _pm) IdleLiquidityHookEnterprise(_pm) {}

    function setPositionATokenPrincipalForTest(
        PoolId pid,
        address lp,
        uint8 side,
        uint256 amount
    ) external onlyOwner {
        if (side == 0) {
            _state().positions[pid][lp].aTokenPrincipal0 = amount;
        } else {
            _state().positions[pid][lp].aTokenPrincipal1 = amount;
        }
    }

    function setAccountingForTest(
        PoolId pid,
        uint8 side,
        uint256 totalATokenPrincipalValue,
        uint256 totalVaultSharesValue,
        uint256 totalIdleLiquidityValue
    ) external onlyOwner {
        _state().totalATokenPrincipal[pid][side] = totalATokenPrincipalValue;
        _state().totalVaultShares[pid][side] = totalVaultSharesValue;
        _state().totalIdleLiquidity[pid][side] = totalIdleLiquidityValue;
    }

    function setPositionStatusForTest(PoolId pid, address lp, uint8 status) external onlyOwner {
        _state().positions[pid][lp].status = Status(status);
    }
}

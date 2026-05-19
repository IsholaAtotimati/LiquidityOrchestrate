// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Status} from "../src/types/IdleLiquidityTypes.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract MockPoolManagerForReenter {
    IdleLiquidityHookEnterprise public hook;

    function setHook(address h) external {
        hook = IdleLiquidityHookEnterprise(h);
    }

    function callRegister(PoolId pid, address lp, uint128 l0, uint128 l1, int24 lower, int24 upper) external {
        hook.registerPosition(pid, lp, l0, l1, lower, upper);
    }

    // minimal stubs to satisfy interface
    function modifyLiquidity(bytes32, bytes memory, bytes memory) external {}
}

contract MockAavePool {
    // minimal withdraw/supply interface used by hook
    function supply(address, uint256, address, uint16) external {
        // no-op for tests
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        // return the requested amount to mimic Aave's withdraw behavior in tests
        return amount;
    }
}

contract ReenterTest is Test {
    event ReenterReady(PoolId indexed pid, address indexed lp);

    IdleLiquidityHookEnterprise hook;
    MockPoolManagerForReenter pm;
    address ownerAddr;

    function setUp() public {
        pm = new MockPoolManagerForReenter();
        hook = new IdleLiquidityHookEnterprise(address(pm));
        pm.setHook(address(hook));
        ownerAddr = address(this);
    }

    function test_prepareReenterBatch_withdraws_and_emits() public {
        PoolId pid = PoolId.wrap(bytes32(uint256(2)));
        uint8 side = 0;
        address lp = address(0xBEEF);

        // register lp via pool manager
        pm.callRegister(pid, lp, uint128(1 ether), 0, int24(-120), int24(120));

        // deploy mock aToken and aave pool and set pool config
        ERC20PresetMinterPauser aToken = new ERC20PresetMinterPauser("aT", "aT");
        MockAavePool aPool = new MockAavePool();

        // set pool config for AAVE (asset/pool/aToken)
        hook.setPoolConfigAave(pid, side, address(0xCAFE), address(aPool), address(aToken), 9000, 1000);

        // set position principal and total accounting
        uint256 principal = 500 ether;
        hook.setPositionATokenPrincipalForTest(pid, lp, side, principal);
        hook.setAccountingForTest(pid, side, principal, 0, principal);

        // mark position IDLE so prepareReenterBatch processes it
        hook.setPositionStatusForTest(pid, lp, uint8(1)); // Status.IDLE == 1

        uint256 beforeIdle = hook.totalIdleLiquidity(pid, side);
        assertEq(beforeIdle, principal);

        // expect ReenterReady emitted and position status to transition back to ACTIVE
        vm.expectEmit(true, true, false, false);
        emit ReenterReady(pid, lp);

        hook.prepareReenterBatch(pid, 0, 1);

        uint256 afterIdle = hook.totalIdleLiquidity(pid, side);
        assertEq(afterIdle, beforeIdle);

        // position should now be active again
        (uint128 liq0, uint128 liq1, int24 lower, int24 upper, Status posStatus, uint256 lastYieldIndex0, uint256 lastYieldIndex1, uint256 accumulatedYield0, uint256 accumulatedYield1, uint256 vaultShares0, uint256 vaultShares1, uint256 a0, uint256 a1) = hook.positions(pid, lp);
        assertEq(uint8(posStatus), uint8(Status.ACTIVE));
    }
}

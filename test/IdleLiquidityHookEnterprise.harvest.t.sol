// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract MockHarvestStrategy {
    function balanceOf(bytes calldata) external pure returns (uint256) {
        return 100 ether;
    }

    function convertToAssets(bytes calldata ctx) external pure returns (uint256) {
        (,,, , uint256 amountOrShares) = abi.decode(ctx, (address, address, address, address, uint256));
        return amountOrShares;
    }
}
// removed unused imports flagged by forge-lint

contract MockPoolManagerForHarvest {
    // minimal stub to satisfy constructor
    function modifyLiquidity(PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata) external {}
    function swap(PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata) external {}
}

contract HarvestTest is Test {
    IdleLiquidityHookEnterprise hook;
    MockHarvestStrategy aaveStrategy;
    address owner;

    function setUp() public {
        MockPoolManagerForHarvest m = new MockPoolManagerForHarvest();
        hook = new IdleLiquidityHookEnterprise(address(m));
        aaveStrategy = new MockHarvestStrategy();
        hook.setAaveStrategy(address(aaveStrategy));
        owner = address(this);
    }

    function test_harvest_updates_globalIndex_for_aToken() public {
        PoolId pid = PoolId.wrap(bytes32(uint256(1)));
        uint8 side = 0;

        // deploy an ERC20 to act as aToken
        ERC20PresetMinterPauser aToken = new ERC20PresetMinterPauser("aT", "aT");

        // set pool config: use dummy addresses for asset/pool
        address asset = address(0xCAFE);
        address pool = address(0xBEEF);
        uint256 lpShare = 9000;
        uint256 protocolShare = 1000;

        // set the aToken and pool via setPoolConfigAave
        hook.setPoolConfigAave(pid, side, asset, pool, address(aToken), lpShare, protocolShare);

        // simulate accounting: set recorded principal to 0 and mark idle liquidity
        uint256 principal = 0;
        hook.setAccountingForTest(pid, side, principal, 0, 1000 ether);

        // mint aToken balance to hook contract (simulate principal + interest present)
        aToken.mint(address(hook), 100 ether);

        // read global index before
        uint256 beforeIdx = hook.globalYieldIndex(pid, side);
        assertEq(beforeIdx, 0);

        // call harvest as owner
        uint256 y = hook.harvest(pid, side);
        assertEq(y, 100 ether);

        // global index must have increased
        uint256 afterIdx = hook.globalYieldIndex(pid, side);
        assertGt(afterIdx, beforeIdx);
    }
}

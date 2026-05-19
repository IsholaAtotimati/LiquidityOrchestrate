// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract IdleLiquidityHookEnterpriseGasTest is Test {
    IdleLiquidityHookEnterprise hook;
    address owner;

    ERC20PresetMinterPauser token0;
    ERC20PresetMinterPauser token1;

    function setUp() public {
        owner = address(this);

        // deploy hook (mock pool manager for simplicity)
        hook = new IdleLiquidityHookEnterprise(address(this));

        token0 = new ERC20PresetMinterPauser("T0", "T0");
        token1 = new ERC20PresetMinterPauser("T1", "T1");

        token0.mint(address(this), 1000 ether);
        token1.mint(address(this), 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        GAS: CONFIG SETUP
    //////////////////////////////////////////////////////////////*/
    function testGas_SetPoolConfig() public {
        PoolId pid = PoolId.wrap(bytes32(uint256(1)));
        // Only update share/protocol BP to save gas (write only two slots)
        hook.updateRates(pid, 9000, 1000);
    }

    function testGas_UpdateRatesBatch() public {
        PoolId[] memory pids = new PoolId[](4);
        uint256[] memory lps = new uint256[](4);
        uint256[] memory prots = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            pids[i] = PoolId.wrap(bytes32(uint256(i + 10)));
            lps[i] = 9000;
            prots[i] = 1000;
        }

        hook.updateRatesBatch(pids, lps, prots);
    }

    /*//////////////////////////////////////////////////////////////
                        GAS: POSITION UPDATE FLOW
    //////////////////////////////////////////////////////////////*/
    function testGas_PositionFlow() public {
        PoolId pid = PoolId.wrap(bytes32(uint256(2)));

        hook.updateRates(pid, 9000, 1000);

        hook.needUpdate(pid);
        // ensure there's at least one tracked LP so rebalance is a no-op rather than revert
        hook.registerLP(pid, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        GAS: REBALANCE
    //////////////////////////////////////////////////////////////*/
    function testGas_Rebalance() public {
        PoolId pid = PoolId.wrap(bytes32(uint256(3)));

        hook.updateRates(pid, 9000, 1000);

        hook.needUpdate(pid);
        // ensure there's at least one tracked LP so rebalance is a no-op rather than revert
        hook.registerLP(pid, address(this));

        // measure rebalance cost
        hook.rebalance(pid, 0, 1);
        // post-rebalance assertions: ensure lastRebalanceBlock updated and upkeep cleared
        uint256 rb = hook.lastRebalanceBlock(pid);
        (bool upkeepAfter,) = hook.checkUpkeep("");
        assertTrue(rb > 0, "lastRebalanceBlock not set");
        assertTrue(!upkeepAfter, "upkeep still needed after rebalance");
    }

    /*//////////////////////////////////////////////////////////////
                        GAS: FULL FLOW SIMULATION
    //////////////////////////////////////////////////////////////*/
    function testGas_FullFlow() public {
        PoolId pid = PoolId.wrap(bytes32(uint256(4)));

        hook.updateRates(pid, 9000, 1000);

        hook.needUpdate(pid);

        // ensure there's at least one tracked LP so rebalance is a no-op rather than revert
        hook.registerLP(pid, address(this));

        hook.rebalance(pid, 0, 1);
        // verify lastRebalanceBlock and upkeep cleared
        uint256 rb2 = hook.lastRebalanceBlock(pid);
        (bool upkeepAfter2,) = hook.checkUpkeep("");
        assertTrue(rb2 > 0, "lastRebalanceBlock not set (fullflow)");
        assertTrue(!upkeepAfter2, "upkeep still needed after rebalance (fullflow)");

        hook.needUpdate(pid);
    }
}
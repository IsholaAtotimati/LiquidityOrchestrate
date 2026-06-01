// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Your hook
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";

contract DeployHookSimple is Script {

    function run() external {
        // ─────────────────────────────────────────────
        // 1. ENV SETUP
        // ─────────────────────────────────────────────
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        require(poolManager != address(0), "Invalid PoolManager");

        // ─────────────────────────────────────────────
        // 2. DEPLOY HOOK
        // ─────────────────────────────────────────────
        vm.startBroadcast(pk);

        IdleLiquidityHookEnterprise hook = new IdleLiquidityHookEnterprise(
            poolManager
        );

        vm.stopBroadcast();

        // ─────────────────────────────────────────────
        // 3. VERIFY & LOG
        // ─────────────────────────────────────────────
        require(address(hook).code.length > 0, "Deployment failed");

        console2.log("Hook deployed successfully at:");
        console2.log(address(hook));
    }
}

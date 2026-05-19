// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Uniswap v4 imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/utils/HookMiner.sol";
// Your hook
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";

contract DeployUnichain is Script{

    function run() external {

        // ─────────────────────────────────────────────
        // 1. ENV SETUP
        // ─────────────────────────────────────────────
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");

        require(poolManager != address(0), "Invalid PoolManager");

        // ─────────────────────────────────────────────
        // 2. HOOK CONFIGURATION
        // ─────────────────────────────────────────────
        // You only use afterSwap → correct flag
        uint160 flags = Hooks.AFTER_SWAP_FLAG;

        // ─────────────────────────────────────────────
        // 3. BYTECODE + CONSTRUCTOR
        // ─────────────────────────────────────────────
        bytes memory bytecode = type(IdleLiquidityHookEnterprise).creationCode;
        bytes memory constructorArgs = abi.encode(poolManager);

        // ─────────────────────────────────────────────
        // 4. FIND VALID HOOK ADDRESS (HookMiner)
        // ─────────────────────────────────────────────
        (address hookAddress, bytes32 salt) =
            HookMiner.find(
                address(this),
                flags,
                bytecode,
                constructorArgs
            );

        console2.log("Predicted hook address:", hookAddress);
        console2.log("Selected salt:", uint256(salt));

        // ─────────────────────────────────────────────
        // 5. DEPLOY VIA CREATE2
        // ─────────────────────────────────────────────
        vm.startBroadcast(pk);

        IdleLiquidityHookEnterprise hook =
            new IdleLiquidityHookEnterprise{salt: salt}(poolManager);

        vm.stopBroadcast();

        // ─────────────────────────────────────────────
        // 6. VERIFY CORRECTNESS
        // ─────────────────────────────────────────────
        require(address(hook) == hookAddress, "Hook address mismatch");
        require(address(hook).code.length > 0, "Deployment failed");

        console2.log("SUCCESS: Valid Uniswap v4 Hook deployed at:");
        console2.log(address(hook));
    }
}
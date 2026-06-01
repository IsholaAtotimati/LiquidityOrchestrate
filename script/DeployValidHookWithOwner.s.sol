// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

// Uniswap v4 imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/utils/HookMiner.sol";
// Your hook
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

contract DeployUnichainWithOwner is Script {
    // HACKATHON MODE: Pre-approved pool ID
    bytes32 constant POOL_ID = 0x09680032ab300a9ad3c27cfb475468b1dbf569c0c54d0c3ba8b0fdaf8e12b388;

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
        // Use the canonical Create2Deployer address for Uniswap v4
        address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        (address hookAddress, bytes32 salt) =
            HookMiner.find(
                create2Deployer,
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

        hook.setApprovedPool(PoolId.wrap(POOL_ID), true);

        console2.log("Hook deployed at:", address(hook));
        console2.log("Hook owner (Create2Deployer):", hook.owner());
        vm.stopBroadcast();

        // ─────────────────────────────────────────────
        // 6. VERIFY CORRECTNESS
        // ─────────────────────────────────────────────
        require(address(hook).code.length > 0, "Deployment failed");
        require(hook.approvedPools(PoolId.wrap(POOL_ID)), "Pool pre-approval failed");

        console2.log("SUCCESS: Hook deployed & pool pre-approved for hackathon!");
        console2.log("  Hook Address:", address(hook));
        console2.log("  Owner: Create2Deployer (0x4e59b44847b379578588920cA78FbF26c0B4956C)");
        console2.log("  PoolManager:", poolManager);
        console2.log("  Pre-Approved Pool ID:", vm.toString(POOL_ID));
        console2.log("");
        console2.log("Public can now interact with the pool without owner privileges!");
    }
}

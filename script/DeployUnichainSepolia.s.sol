// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import {AaveStrategy} from "../src/strategies/aave/AaveStrategy.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {Create2Deployer} from "../src/utils/Create2Deployer.sol";

contract DeployScript is Script {
    function run() external {
        address poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        require(poolManager != address(0), "POOL_MANAGER_ADDRESS not set");

        vm.startBroadcast();

        // Deploy a small Create2 factory (regular deployment). We'll use this factory
        // to deploy both contracts via CREATE2 with fixed salts so addresses are deterministic.
        Create2Deployer factory = new Create2Deployer();
        console.log("Create2Deployer:", address(factory));

        // Prepare AaveStrategy bytecode and salt
        bytes memory aaveCode = type(AaveStrategy).creationCode;
        bytes32 saltAave = keccak256(abi.encodePacked("AAVE_SALT_V1"));
        bytes32 aaveHash = keccak256(aaveCode);
        address predictedAave = factory.computeAddress(saltAave, aaveHash, address(factory));
        console.log("predicted AaveStrategy:", predictedAave);

        factory.deploy(aaveCode, saltAave);
        address aaveAddr = predictedAave;
        console.log("deployed AaveStrategy:", aaveAddr);

        // Prepare Hook bytecode (include constructor arg) and salt
        bytes memory hookCode = abi.encodePacked(type(IdleLiquidityHookEnterprise).creationCode, abi.encode(poolManager));
        bytes32 saltHook = keccak256(abi.encodePacked("HOOK_SALT_V1"));
        bytes32 hookHash = keccak256(hookCode);
        address predictedHook = factory.computeAddress(saltHook, hookHash, address(factory));
        console.log("predicted Hook:", predictedHook);

        factory.deploy(hookCode, saltHook);
        address hookAddr = predictedHook;
        console.log("deployed Hook:", hookAddr);

        // Wire up Aave strategy address on the hook. The hook owner is the Create2 factory,
        // so the factory must perform this call.
        factory.call(hookAddr, abi.encodeWithSelector(IdleLiquidityHookEnterprise.setAaveStrategy.selector, aaveAddr));
        console.log("setAaveStrategy ->", aaveAddr);

        vm.stopBroadcast();
    }
}

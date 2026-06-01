// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";

contract TestCallback is IUnlockCallback {
    IPoolManager immutable poolManager;
    string public lastError;
    bool public initialized;
    
    constructor(address pm) {
        poolManager = IPoolManager(pm);
    }
    
    function testUnlock() external {
        poolManager.unlock("");
    }
    
    function unlockCallback(bytes calldata) external override returns (bytes memory) {
        initialized = true;
        return "";
    }
}

contract DeployTest is Script {
    function run() external {
        address POOL_MANAGER = 0x07113ac3aD503BA086cB3a7Aa3BF6E99b8856113;
        
        vm.startBroadcast();
        
        // Deploy test callback
        TestCallback callback = new TestCallback(POOL_MANAGER);
        console2.log("TestCallback deployed at:", address(callback));
        
        // Try to call testUnlock
        try callback.testUnlock() {
            console2.log("testUnlock succeeded!");
            console2.log("Initialized:", callback.initialized());
        } catch Error(string memory reason) {
            console2.log("testUnlock failed with reason:", reason);
        } catch Panic(uint errorCode) {
            console2.log("testUnlock failed with panic:", errorCode);
        }  catch (bytes memory data) {
            console2.log("testUnlock failed with data");
        }
        
        vm.stopBroadcast();
    }
}

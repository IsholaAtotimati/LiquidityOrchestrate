// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/// @notice Minimal initializer for testing
contract MinimalInitializer is IUnlockCallback {
    IPoolManager immutable poolManager;
    
    constructor(address pm) {
        poolManager = IPoolManager(pm);
    }
    
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external {
        poolManager.unlock(abi.encode(key, sqrtPriceX96));
    }
    
    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(poolManager), "Unauthorized");
        (PoolKey memory key, uint160 sqrtPriceX96) = abi.decode(data, (PoolKey, uint160));
        poolManager.initialize(key, sqrtPriceX96);
        return "";
    }
}

contract InitializePoolScript is Script {
    function run() external {
        address POOL_MANAGER = 0x07113ac3aD503BA086cB3a7Aa3BF6E99b8856113;
        address TOKEN0 = 0x05aC9Ae0cCc5D7D8a8F11F0104466c644B89EA00;
        address TOKEN1 = 0x66dDb696Db92425b2523fa3CbAbb69a5e8B5C3fC;
        uint24 FEE = 3000;
        int24 TICK_SPACING = 60;
        uint160 SQRT_PRICE_X96 = 2**96;
        
        vm.startBroadcast();
        
        // Deploy initializer
        MinimalInitializer initializer = new MinimalInitializer(POOL_MANAGER);
        // Initializer deployed
        
        // Create pool key with zero hook
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(TOKEN0),
            currency1: Currency.wrap(TOKEN1),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
        
        // Initialize pool
        initializer.initialize(poolKey, SQRT_PRICE_X96);
        // Pool initialized successfully
        
        vm.stopBroadcast();
    }
}

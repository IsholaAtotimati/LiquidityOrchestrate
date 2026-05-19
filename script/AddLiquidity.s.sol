// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract AddLiquidityScript is Script {
    function run() external {
        address pmAddr = vm.envAddress("POOL_MANAGER_ADDRESS");
        address hookAddr = vm.envAddress("HOOK_ADDRESS");
        address token0 = vm.envAddress("TOKEN0_ADDRESS");
        address token1 = vm.envAddress("TOKEN1_ADDRESS");

        require(pmAddr != address(0) && hookAddr != address(0) && token0 != address(0) && token1 != address(0), "set POOL_MANAGER_ADDRESS, HOOK_ADDRESS, TOKEN0_ADDRESS, TOKEN1_ADDRESS");

        uint24 fee = uint24(vm.envUint("FEE") == 0 ? 3000 : vm.envUint("FEE"));
        uint256 tsRaw = vm.envUint("TICK_SPACING");
        if (tsRaw == 0) tsRaw = 60;
        require(tsRaw <= uint256(uint24(type(int24).max)), "TICK_SPACING too large");
        int24 tickSpacing = int24(int256(uint256(tsRaw)));

        // defaults
        int24 tickLower = int24(-120);
        int24 tickUpper = int24(120);
        uint256 liquidity = vm.envUint("LIQUIDITY");
        if (liquidity == 0) liquidity = 1e18;

        // build PoolKey and params
        PoolKey memory key = PoolKey({currency0: Currency.wrap(token0), currency1: Currency.wrap(token1), fee: fee, tickSpacing: tickSpacing, hooks: IHooks(hookAddr)});
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: int256(liquidity), salt: bytes32(0)});

        IPoolManager pm = IPoolManager(pmAddr);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        // try initialize (may revert if already initialized)
        try pm.initialize(key, uint160(1 << 96)) {
        } catch {}

        pm.modifyLiquidity(key, params, "");
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {StrategyManager} from "../src/managers/StrategyManager.sol";
import {StrategyExecutor} from "../src/strategies/StrategyExecutor.sol";
import {AaveStrategy} from "../src/strategies/aave/AaveStrategy.sol";
import {ERC4626Strategy} from "../src/strategies/vaults/ERC4626Strategy.sol";
import {MockPoolManager} from "./ProofOfMovement.s.sol";

contract DebugProofOfMovementScript is Script {
    function run() external {
        string memory rpcUrl = vm.envString("UNICHAIN_RPC_URL");
        require(bytes(rpcUrl).length > 0, "env UNICHAIN_RPC_URL required");
        vm.createSelectFork(rpcUrl);

        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        require(pk != 0, "env DEPLOYER_PRIVATE_KEY required");
        address owner = vm.addr(pk);

        address token0 = vm.envAddress("TOKEN0_ADDRESS");
        address token1 = vm.envAddress("TOKEN1_ADDRESS");
        require(token0 != address(0) && token1 != address(0), "TOKEN0_ADDRESS and TOKEN1_ADDRESS required");

        address aaveAsset = vm.envAddress("AAVE_ASSET_ADDRESS");
        address aToken = vm.envAddress("ATOKEN_ADDRESS");
        address aavePool = vm.envAddress("AAVE_POOL_ADDRESS");
        address aavePriceFeed = vm.envAddress("AAVE_PRICE_FEED");
        address aaveWhale = vm.envAddress("AAVE_ASSET_WHALE");
        require(aaveAsset != address(0) && aToken != address(0) && aavePool != address(0) && aavePriceFeed != address(0), "Aave config missing");
        require(aaveWhale != address(0), "AAVE_ASSET_WHALE required");

        MockPoolManager poolManager = new MockPoolManager();
        IdleLiquidityHookEnterprise hook = new IdleLiquidityHookEnterprise(address(poolManager));
        StrategyManager strategyManager = new StrategyManager(owner);
        StrategyExecutor strategyExecutor = new StrategyExecutor();
        AaveStrategy aaveStrategy = new AaveStrategy();
        ERC4626Strategy erc4626Strategy = new ERC4626Strategy();

        vm.prank(owner);
        strategyManager.setExecutor(address(strategyExecutor));
        hook.setStrategyManager(address(strategyManager));
        hook.setAaveStrategy(address(aaveStrategy));
        hook.setERC4626Strategy(address(erc4626Strategy));
        hook.setApprovedPool(pidFor(token0, token1, address(hook)), true);
        hook.setTrustedAavePool(aavePool, true);
        hook.setPriceFeed(aaveAsset, aavePriceFeed);
        hook.setPoolConfigAave(pidFor(token0, token1, address(hook)), 0, aaveAsset, aavePool, aToken, 0, 0);

        PoolId pid = pidFor(token0, token1, address(hook));
        (int24 lowerTick, int24 upperTick) = makeOutOfRangeTicks(poolManager);

        vm.prank(address(poolManager));
        hook.registerPosition(pid, owner, uint128(1e18), uint128(0), lowerTick, upperTick);
        fundIfNeeded(aaveAsset, address(hook), aaveWhale, 1e18);

        uint256 beforeAsset = IERC20(aaveAsset).balanceOf(address(hook));
        uint256 beforeAToken = IERC20(aToken).balanceOf(address(hook));
        console.log("=== BEFORE REBALANCE ===");
        console.log("Aave asset balance before", beforeAsset);
        console.log("Aave aToken balance before", beforeAToken);

        hook.needUpdate(pid);
        vm.recordLogs();
        hook.rebalance(pid, 0, 10);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 afterAsset = IERC20(aaveAsset).balanceOf(address(hook));
        uint256 afterAToken = IERC20(aToken).balanceOf(address(hook));
        console.log("=== AFTER REBALANCE ===");
        console.log("Aave asset balance after", afterAsset);
        console.log("Aave aToken balance after", afterAToken);
        console.log("Aave asset delta", diff(beforeAsset, afterAsset));
        console.log("Aave aToken delta", diff(beforeAToken, afterAToken));
        console.log("totalATokenPrincipal", hook.totalATokenPrincipal(pid, 0));
        console.log("captured logs", logs.length);
    }

    function diff(uint256 before, uint256 afterValue) internal pure returns (uint256) {
        return before > afterValue ? before - afterValue : afterValue - before;
    }

    function makeOutOfRangeTicks(MockPoolManager poolManager) internal view returns (int24 lowerTick, int24 upperTick) {
        bytes32 encoded = poolManager.extsload(bytes32(0));
        uint24 rawTick = uint24(uint256(encoded >> 160));
        int24 currentTick = int24(rawTick);
        if (currentTick >= 0) {
            lowerTick = currentTick + 10;
            upperTick = currentTick + 110;
        } else {
            upperTick = currentTick - 10;
            lowerTick = currentTick - 110;
        }
    }

    function pidFor(address token0, address token1, address hookAddr) internal pure returns (PoolId) {
        return PoolIdLibrary.toId(PoolKey({currency0: Currency.wrap(token0), currency1: Currency.wrap(token1), fee: 3000, tickSpacing: 60, hooks: IHooks(hookAddr)}));
    }

    function fundIfNeeded(address asset, address receiver, address whale, uint256 amount) internal {
        if (IERC20(asset).balanceOf(receiver) >= amount) {
            return;
        }
        vm.startPrank(whale);
        require(IERC20(asset).transfer(receiver, amount), "asset transfer failed");
        vm.stopPrank();
    }
}

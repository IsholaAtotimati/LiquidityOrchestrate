// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
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
import {Vm} from "forge-std/Vm.sol";

contract ProofOfMovementScript is Script {
    struct DepositInfo {
        address asset;
        address aToken;
        address aavePool;
        address priceFeed;
        address whale;
        uint256 amount;
    }

    function run() external {
        string memory rpcUrl = vm.envString("UNICHAIN_RPC_URL");
        require(bytes(rpcUrl).length > 0, "env UNICHAIN_RPC_URL required");
        vm.createSelectFork(rpcUrl);

        uint256 pk = 0;
        try vm.envUint("PRIVATE_KEY") returns (uint256 value) {
            pk = value;
        } catch {}
        if (pk == 0) {
            try vm.envUint("DEPLOYER_PRIVATE_KEY") returns (uint256 value) {
                pk = value;
            } catch {}
        }
        require(pk != 0, "env PRIVATE_KEY or DEPLOYER_PRIVATE_KEY required");
        address owner = vm.addr(pk);
        vm.deal(owner, 10 ether);

        address token0 = address(0);
        address token1 = address(0);
        try vm.envAddress("TOKEN0_ADDRESS") returns (address addr0) {
            token0 = addr0;
        } catch {}
        try vm.envAddress("TOKEN1_ADDRESS") returns (address addr1) {
            token1 = addr1;
        } catch {}
        require(token0 != address(0) && token1 != address(0), "TOKEN0_ADDRESS and TOKEN1_ADDRESS required");

        DepositInfo memory aaveInfo = DepositInfo({
            asset: address(0),
            aToken: address(0),
            aavePool: address(0),
            priceFeed: address(0),
            whale: address(0),
            amount: 0
        });
        try vm.envAddress("AAVE_ASSET_ADDRESS") returns (address addr) {
            aaveInfo.asset = addr;
        } catch {}
        try vm.envAddress("ATOKEN_ADDRESS") returns (address addr) {
            aaveInfo.aToken = addr;
        } catch {}
        try vm.envAddress("AAVE_POOL_ADDRESS") returns (address addr) {
            aaveInfo.aavePool = addr;
        } catch {}
        try vm.envAddress("AAVE_PRICE_FEED") returns (address addr) {
            aaveInfo.priceFeed = addr;
        } catch {}
        try vm.envAddress("AAVE_ASSET_WHALE") returns (address addr) {
            aaveInfo.whale = addr;
        } catch {}
        try vm.envUint("DEPOSIT_AMOUNT") returns (uint256 value) {
            aaveInfo.amount = value;
        } catch {}
        if (aaveInfo.amount == 0) {
            aaveInfo.amount = 1e18;
        }

        address vault = address(0);
        address vaultAsset = address(0);
        address vaultPriceFeed = address(0);
        address vaultWhale = address(0);
        uint256 vaultAmount = 0;
        try vm.envAddress("ERC4626_VAULT_ADDRESS") returns (address addr) {
            vault = addr;
        } catch {}
        try vm.envAddress("ERC4626_ASSET_ADDRESS") returns (address addr) {
            vaultAsset = addr;
        } catch {}
        try vm.envAddress("ERC4626_PRICE_FEED") returns (address addr) {
            vaultPriceFeed = addr;
        } catch {}
        try vm.envAddress("ERC4626_ASSET_WHALE") returns (address addr) {
            vaultWhale = addr;
        } catch {}
        try vm.envUint("ERC4626_DEPOSIT_AMOUNT") returns (uint256 value) {
            vaultAmount = value;
        } catch {}
        if (vaultAmount == 0) {
            vaultAmount = 1e18;
        }

        bool hasAave = aaveInfo.asset != address(0);
        bool hasVault = vault != address(0);
        if (hasAave) {
            require(aaveInfo.aToken != address(0) && aaveInfo.aavePool != address(0) && aaveInfo.priceFeed != address(0), "Aave config missing: AAVE_ASSET_ADDRESS + ATOKEN_ADDRESS + AAVE_POOL_ADDRESS + AAVE_PRICE_FEED");
        }
        if (hasVault) {
            require(vaultAsset != address(0) && vaultPriceFeed != address(0), "ERC4626 config missing: ERC4626_VAULT_ADDRESS + ERC4626_ASSET_ADDRESS + ERC4626_PRICE_FEED");
        }

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

        if (aaveInfo.asset != address(0)) {
            hook.setTrustedAavePool(aaveInfo.aavePool, true);
            hook.setPriceFeed(aaveInfo.asset, aaveInfo.priceFeed);
            hook.setPoolConfigAave(
                pidFor(token0, token1, address(hook)),
                0,
                aaveInfo.asset,
                aaveInfo.aavePool,
                aaveInfo.aToken,
                0,
                0
            );
        }

        if (vault != address(0)) {
            hook.setTrustedERC4626Vault(vault, true);
            hook.setPriceFeed(vaultAsset, vaultPriceFeed);
            setVaultConfig(address(hook), pidFor(token0, token1, address(hook)), 1, vault, vaultAsset);
        }

        PoolId pid = pidFor(token0, token1, address(hook));
        (int24 lowerTick, int24 upperTick) = makeOutOfRangeTicks(poolManager);

        vm.prank(address(poolManager));
        hook.registerPosition(pid, owner, uint128(aaveInfo.amount), uint128(vaultAmount), lowerTick, upperTick);

        if (aaveInfo.asset != address(0)) {
            fundIfNeeded(aaveInfo.asset, address(hook), aaveInfo.whale, aaveInfo.amount);
        }
        if (vault != address(0)) {
            fundIfNeeded(vaultAsset, address(hook), vaultWhale, vaultAmount);
        }

        uint256 beforeAaveAsset = 0;
        uint256 beforeAToken = 0;
        if (aaveInfo.asset != address(0)) {
            beforeAaveAsset = IERC20(aaveInfo.asset).balanceOf(address(hook));
            beforeAToken = IERC20(aaveInfo.aToken).balanceOf(address(hook));
        }

        uint256 beforeVaultAsset = 0;
        uint256 beforeVaultShares = 0;
        if (vault != address(0)) {
            beforeVaultAsset = IERC20(vaultAsset).balanceOf(address(hook));
            beforeVaultShares = IERC4626(vault).balanceOf(address(hook));
        }

        console.log("=== BEFORE ===");
        if (aaveInfo.asset != address(0)) {
            console.log("Aave asset balance before", beforeAaveAsset);
            console.log("Aave aToken balance before", beforeAToken);
        }
        if (vault != address(0)) {
            console.log("Vault asset balance before", beforeVaultAsset);
            console.log("Vault share balance before", beforeVaultShares);
        }

        hook.needUpdate(pid);
        vm.recordLogs();
        hook.rebalance(pid, 0, 10);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 afterAaveAsset = 0;
        uint256 afterAToken = 0;
        if (aaveInfo.asset != address(0)) {
            afterAaveAsset = IERC20(aaveInfo.asset).balanceOf(address(hook));
            afterAToken = IERC20(aaveInfo.aToken).balanceOf(address(hook));
        }

        uint256 afterVaultAsset = 0;
        uint256 afterVaultShares = 0;
        if (vault != address(0)) {
            afterVaultAsset = IERC20(vaultAsset).balanceOf(address(hook));
            afterVaultShares = IERC4626(vault).balanceOf(address(hook));
        }

        console.log("=== AFTER ===");
        if (aaveInfo.asset != address(0)) {
            console.log("Aave asset balance after", afterAaveAsset);
            console.log("Aave aToken balance after", afterAToken);
            console.log("Aave asset delta", diff(beforeAaveAsset, afterAaveAsset));
            console.log("Aave aToken delta", diff(beforeAToken, afterAToken));
            console.log("Aave totalATokenPrincipal", hook.totalATokenPrincipal(pid, 0));
        }
        if (vault != address(0)) {
            console.log("Vault asset balance after", afterVaultAsset);
            console.log("Vault share balance after", afterVaultShares);
            console.log("Vault asset delta", diff(beforeVaultAsset, afterVaultAsset));
            console.log("Vault share delta", diff(beforeVaultShares, afterVaultShares));
            console.log("Vault totalVaultShares", hook.totalVaultShares(pid, 1));
        }

        (uint128 liq0, uint128 liq1, int24 lower, int24 upper, , , , , , uint256 vaultShares0, uint256 vaultShares1, uint256 aTokenPrincipal0, uint256 aTokenPrincipal1) = hook.positions(pid, owner);
        console.log("LP position liquidity0", liq0);
        console.log("LP position liquidity1", liq1);
        console.log("LP position lowerTick", lower);
        console.log("LP position upperTick", upper);
        console.log("LP position vaultShares0", vaultShares0);
        console.log("LP position vaultShares1", vaultShares1);
        console.log("LP position aTokenPrincipal0", aTokenPrincipal0);
        console.log("Hook tracked LP count", hook.getTrackedLPs(pid).length);
        console.log("Hook totalIdleLiquidity side0", hook.totalIdleLiquidity(pid, 0));
        console.log("Hook totalIdleLiquidity side1", hook.totalIdleLiquidity(pid, 1));

        console.log("=== LOGS ===");
        console.log("captured logs", logs.length);
        for (uint256 i = 0; i < logs.length; ++i) {
            console.log("log index", i);
            console.log("topics", logs[i].topics.length);
            console.log("data len", logs[i].data.length);
            if (logs[i].topics.length > 0) {
                console.logBytes32(logs[i].topics[0]);
            }
        }

    }

    function diff(uint256 before, uint256 afterValue) internal pure returns (uint256) {
        return before > afterValue ? before - afterValue : afterValue - before;
    }

    function pidFor(address token0, address token1, address hookAddr) internal pure returns (PoolId) {
        return PoolIdLibrary.toId(PoolKey({currency0: Currency.wrap(token0), currency1: Currency.wrap(token1), fee: 3000, tickSpacing: 60, hooks: IHooks(hookAddr)}));
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

    function makeInRangeTicks(MockPoolManager poolManager) internal view returns (int24 lowerTick, int24 upperTick) {
        // Create ticks that INCLUDE the current pool tick so position is IN RANGE
        // This will trigger token movement on rebalance
        bytes32 encoded = poolManager.extsload(bytes32(0));
        uint24 rawTick = uint24(uint256(encoded >> 160));
        int24 currentTick = int24(rawTick);
        // Place current tick in the middle of the range
        lowerTick = currentTick - 50;
        upperTick = currentTick + 50;
    }

    function setVaultConfig(address hook, PoolId pid, uint256 side, address vault, address asset) internal {
        require(vault != address(0), "vault required");
        bytes32 storageSlot = keccak256(abi.encodePacked(pid, uint256(0)));
        uint256 start = uint256(storageSlot) + side * 6;
        vm.store(hook, bytes32(start + 0), bytes32(uint256(uint160(vault))));
        vm.store(hook, bytes32(start + 1), bytes32(uint256(0)));
        vm.store(hook, bytes32(start + 2), bytes32(uint256(0)));
        vm.store(hook, bytes32(start + 3), bytes32(uint256(uint160(asset))));
        vm.store(hook, bytes32(start + 4), bytes32(uint256(0)));
        vm.store(hook, bytes32(start + 5), bytes32(uint256(0)));
    }

    function fundIfNeeded(address asset, address receiver, address whale, uint256 amount) internal {
        if (IERC20(asset).balanceOf(receiver) >= amount) {
            return;
        }
        address sender = whale;
        if (sender == address(0)) {
            sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        }
        vm.startPrank(sender);
        require(IERC20(asset).transfer(receiver, amount), "asset transfer failed");
        vm.stopPrank();
    }
}

contract MockPoolManager {
    function initialize(PoolKey calldata, uint160) external {}

    function extsload(bytes32) external pure returns (bytes32) {
        return bytes32(uint256(0));
    }
}

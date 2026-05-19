// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
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

/**
 * @notice ProofOfTokenMovement - Demonstrates actual token movement in/out of idle pools
 *
 * Strategy:
 * 1. Register position with ACTIVE status and IN-RANGE ticks
 * 2. Force position to OUT-OF-RANGE by moving pool tick
 * 3. Rebalance: ACTIVE + OUT-OF-RANGE → moves to IDLE (deposits to aave/erc4626)
 * 4. Restore ticks to IN-RANGE
 * 5. Rebalance again: IDLE + IN-RANGE → moves to ACTIVE (withdraws from aave/erc4626)
 * 6. Observe token movement in both directions
 */
contract ProofOfTokenMovementScript is Script {
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
        require(token0 != address(0) && token1 != address(0), "TOKEN0_ADDRESS + TOKEN1_ADDRESS required");

        address aaveAsset = address(0);
        address aToken = address(0);
        address aavePool = address(0);
        address aavePriceFeed = address(0);
        address aaveWhale = address(0);
        uint256 aaveAmount = 1e18;

        try vm.envAddress("AAVE_ASSET_ADDRESS") returns (address addr) {
            aaveAsset = addr;
        } catch {}
        try vm.envAddress("ATOKEN_ADDRESS") returns (address addr) {
            aToken = addr;
        } catch {}
        try vm.envAddress("AAVE_POOL_ADDRESS") returns (address addr) {
            aavePool = addr;
        } catch {}
        try vm.envAddress("AAVE_PRICE_FEED") returns (address addr) {
            aavePriceFeed = addr;
        } catch {}
        try vm.envAddress("AAVE_ASSET_WHALE") returns (address addr) {
            aaveWhale = addr;
        } catch {}
        try vm.envUint("AAVE_DEPOSIT_AMOUNT") returns (uint256 value) {
            aaveAmount = value;
        } catch {}
        if (aaveAmount == 0) {
            aaveAmount = 1e18;
        }

        DepositInfo memory aaveInfo = DepositInfo({
            asset: aaveAsset,
            aToken: aToken,
            aavePool: aavePool,
            priceFeed: aavePriceFeed,
            whale: aaveWhale,
            amount: aaveAmount
        });

        address vault = address(0);
        address vaultAsset = address(0);
        address vaultPriceFeed = address(0);
        address vaultWhale = address(0);
        uint256 vaultAmount = 1e18;

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
            require(aaveInfo.aToken != address(0) && aaveInfo.aavePool != address(0) && aaveInfo.priceFeed != address(0), "Aave config missing");
        }
        if (hasVault) {
            require(vaultAsset != address(0) && vaultPriceFeed != address(0), "ERC4626 config missing");
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

        // Start with IN-RANGE ticks
        (int24 lowerTick, int24 upperTick) = makeInRangeTicks(poolManager);
        console.log("=== PHASE 1: Register Position IN-RANGE ===");
        console.log("lowerTick", lowerTick);
        console.log("upperTick", upperTick);

        vm.prank(address(poolManager));
        hook.registerPosition(pid, owner, uint128(aaveInfo.amount), uint128(vaultAmount), lowerTick, upperTick);

        if (aaveInfo.asset != address(0)) {
            fundIfNeeded(aaveInfo.asset, address(hook), aaveInfo.whale, aaveInfo.amount);
        }
        if (vault != address(0)) {
            fundIfNeeded(vaultAsset, address(hook), vaultWhale, vaultAmount);
        }

        console.log("=== PHASE 2: Position OUT-OF-RANGE (force idle conversion) ===");
        // Force position OUT-OF-RANGE by moving pool tick
        poolManager.setTick(100); // Move tick outside [lowerTick, upperTick]
        
        uint256 beforeAaveAsset = IERC20(aaveInfo.asset).balanceOf(address(hook));
        uint256 beforeAToken = IERC20(aaveInfo.aToken).balanceOf(address(hook));
        uint256 beforeVaultAsset = IERC20(vaultAsset).balanceOf(address(hook));
        uint256 beforeVaultShares = IERC4626(vault).balanceOf(address(hook));

        console.log("Before moveToIdle:");
        console.log("  Aave asset balance", beforeAaveAsset);
        console.log("  Aave aToken balance", beforeAToken);
        console.log("  Vault asset balance", beforeVaultAsset);
        console.log("  Vault share balance", beforeVaultShares);

        hook.needUpdate(pid);
        hook.rebalance(pid, 0, 10);

        uint256 afterIdle_AaveAsset = IERC20(aaveInfo.asset).balanceOf(address(hook));
        uint256 afterIdle_AToken = IERC20(aaveInfo.aToken).balanceOf(address(hook));
        uint256 afterIdle_VaultAsset = IERC20(vaultAsset).balanceOf(address(hook));
        uint256 afterIdle_VaultShares = IERC4626(vault).balanceOf(address(hook));

        console.log("After rebalance to IDLE:");
        console.log("  Aave asset balance", afterIdle_AaveAsset);
        console.log("  Aave aToken balance", afterIdle_AToken);
        console.log("  Aave aToken delta (should be positive = deposit)", diff(beforeAToken, afterIdle_AToken));
        console.log("  Aave asset delta", diff(beforeAaveAsset, afterIdle_AaveAsset));
        console.log("  Vault asset balance", afterIdle_VaultAsset);
        console.log("  Vault share balance", afterIdle_VaultShares);
        console.log("  Vault share delta (should be positive = deposit)", diff(beforeVaultShares, afterIdle_VaultShares));
        console.log("  Vault asset delta", diff(beforeVaultAsset, afterIdle_VaultAsset));

        console.log("=== PHASE 3: Position back IN-RANGE (restore active) ===");
        // Restore to IN-RANGE
        poolManager.setTick(0); // Move tick back to in-range
        
        uint256 beforeActive_AaveAsset = IERC20(aaveInfo.asset).balanceOf(address(hook));
        uint256 beforeActive_AToken = IERC20(aaveInfo.aToken).balanceOf(address(hook));
        uint256 beforeActive_VaultAsset = IERC20(vaultAsset).balanceOf(address(hook));
        uint256 beforeActive_VaultShares = IERC4626(vault).balanceOf(address(hook));

        console.log("Before moveToActive:");
        console.log("  Aave asset balance", beforeActive_AaveAsset);
        console.log("  Aave aToken balance", beforeActive_AToken);
        console.log("  Vault asset balance", beforeActive_VaultAsset);
        console.log("  Vault share balance", beforeActive_VaultShares);

        hook.needUpdate(pid);
        hook.rebalance(pid, 0, 10);

        uint256 afterActive_AaveAsset = IERC20(aaveInfo.asset).balanceOf(address(hook));
        uint256 afterActive_AToken = IERC20(aaveInfo.aToken).balanceOf(address(hook));
        uint256 afterActive_VaultAsset = IERC20(vaultAsset).balanceOf(address(hook));
        uint256 afterActive_VaultShares = IERC4626(vault).balanceOf(address(hook));

        console.log("After rebalance back to ACTIVE:");
        console.log("  Aave asset balance", afterActive_AaveAsset);
        console.log("  Aave aToken balance", afterActive_AToken);
        console.log("  Aave aToken delta (should be negative = withdraw)", diff(beforeActive_AToken, afterActive_AToken));
        console.log("  Aave asset delta", diff(beforeActive_AaveAsset, afterActive_AaveAsset));
        console.log("  Vault asset balance", afterActive_VaultAsset);
        console.log("  Vault share balance", afterActive_VaultShares);
        console.log("  Vault share delta (should be negative = withdraw)", diff(beforeActive_VaultShares, afterActive_VaultShares));
        console.log("  Vault asset delta", diff(beforeActive_VaultAsset, afterActive_VaultAsset));

        (uint128 liq0, uint128 liq1, , , , , , , , uint256 vaultShares0, uint256 vaultShares1, uint256 aTokenPrincipal0, ) = hook.positions(pid, owner);
        console.log("=== FINAL POSITION STATE ===");
        console.log("liquidity0", liq0);
        console.log("liquidity1", liq1);
        console.log("vaultShares0", vaultShares0);
        console.log("vaultShares1", vaultShares1);
        console.log("aTokenPrincipal0", aTokenPrincipal0);
    }

    function diff(uint256 before, uint256 afterValue) internal pure returns (uint256) {
        return before > afterValue ? before - afterValue : afterValue - before;
    }

    function pidFor(address token0, address token1, address hookAddr) internal pure returns (PoolId) {
        return PoolIdLibrary.toId(PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        }));
    }

    function makeInRangeTicks(MockPoolManager poolManager) internal view returns (int24 lowerTick, int24 upperTick) {
        int24 currentTick = poolManager.getTick();
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
    int24 private currentTick = 0;

    function getTick() external view returns (int24) {
        return currentTick;
    }

    function setTick(int24 newTick) external {
        currentTick = newTick;
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        if (slot == bytes32(0)) {
            return bytes32(uint256(uint24(uint256(int256(currentTick))))) << 160;
        }
        return bytes32(0);
    }
}

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
 * @notice DemoTokenMovement - Shows token movement via direct API calls
 * 
 * This bypasses the complex rebalance state machine to directly show
 * token deposits/withdrawals working correctly.
 */
contract DemoTokenMovementScript is Script {
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

        bool hasAave = aaveAsset != address(0);
        bool hasVault = vault != address(0);

        console.log("=== SETUP ===");
        console.log("aaveAsset", aaveAsset);
        console.log("vault", vault);
        console.log("amount", aaveAmount);

        // Create strategy instances
        AaveStrategy aaveStrategy = new AaveStrategy();
        ERC4626Strategy erc4626Strategy = new ERC4626Strategy();
        
        // Fund an account that acts as the "hook"
        address hookLike = owner;
        
        if (hasAave) {
            fundIfNeeded(aaveAsset, hookLike, aaveWhale, aaveAmount);
        }
        if (hasVault) {
            fundIfNeeded(vaultAsset, hookLike, vaultWhale, vaultAmount);
        }

        console.log("=== AAVE DEPOSIT DEMO ===");
        if (hasAave) {
            uint256 beforeAsset = IERC20(aaveAsset).balanceOf(hookLike);
            uint256 beforeAToken = IERC20(aToken).balanceOf(hookLike);
            console.log("Before deposit:");
            console.log("  asset balance", beforeAsset);
            console.log("  aToken balance", beforeAToken);

            // Approve strategy to spend asset
            IERC20(aaveAsset).approve(address(aaveStrategy), aaveAmount);

            // Call strategy deposit (this should move tokens)
            bytes memory ctx = abi.encode(
                address(aavePool),
                aToken,
                address(0),  // vault (not used)
                aaveAsset,
                aaveAmount
            );

            try aaveStrategy.deposit(ctx) returns (uint256 result) {
                console.log("Strategy deposit succeeded, got", result, "aTokens");
            } catch Error(string memory reason) {
                console.log("Strategy deposit failed:", reason);
            } catch (bytes memory reason) {
                console.log("Strategy deposit failed with bytes");
            }

            uint256 afterAsset = IERC20(aaveAsset).balanceOf(hookLike);
            uint256 afterAToken = IERC20(aToken).balanceOf(hookLike);
            console.log("After deposit:");
            console.log("  asset balance", afterAsset);
            console.log("  aToken balance", afterAToken);
            console.log("  asset delta (should lose aaveAmount):", beforeAsset - afterAsset);
            console.log("  aToken delta (should gain):", afterAToken - beforeAToken);
        }

        console.log("=== ERC4626 DEPOSIT DEMO ===");
        if (hasVault) {
            uint256 beforeAsset = IERC20(vaultAsset).balanceOf(hookLike);
            uint256 beforeShares = IERC4626(vault).balanceOf(hookLike);
            console.log("Before deposit:");
            console.log("  asset balance", beforeAsset);
            console.log("  share balance", beforeShares);

            // Approve strategy to spend asset
            IERC20(vaultAsset).approve(address(erc4626Strategy), vaultAmount);

            // Call strategy deposit
            bytes memory ctx = abi.encode(
                address(0),  // aavePool (not used)
                address(0),  // aToken (not used)
                vault,
                vaultAsset,
                vaultAmount
            );

            try erc4626Strategy.deposit(ctx) returns (uint256 result) {
                console.log("Strategy deposit succeeded, got", result, "shares");
            } catch Error(string memory reason) {
                console.log("Strategy deposit failed:", reason);
            } catch (bytes memory reason) {
                console.log("Strategy deposit failed with bytes");
            }

            uint256 afterAsset = IERC20(vaultAsset).balanceOf(hookLike);
            uint256 afterShares = IERC4626(vault).balanceOf(hookLike);
            console.log("After deposit:");
            console.log("  asset balance", afterAsset);
            console.log("  share balance", afterShares);
            console.log("  asset delta (should lose vaultAmount):", beforeAsset - afterAsset);
            console.log("  share delta (should gain):", afterShares - beforeShares);
        }

        console.log("=== TOKEN MOVEMENT COMPLETE ===");
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

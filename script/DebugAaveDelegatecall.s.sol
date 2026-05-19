// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {AaveStrategy} from "../src/strategies/aave/AaveStrategy.sol";

contract DebugAaveDelegatecall is Script {
    function run() external {
        string memory rpcUrl = vm.envString("UNICHAIN_RPC_URL");
        vm.createSelectFork(rpcUrl);
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.addr(pk);
        address asset = vm.envAddress("AAVE_ASSET_ADDRESS");
        address aToken = vm.envAddress("ATOKEN_ADDRESS");
        address aavePool = vm.envAddress("AAVE_POOL_ADDRESS");
        address whale = vm.envAddress("AAVE_ASSET_WHALE");
        uint256 amount = vm.envUint("DEPOSIT_AMOUNT");
        if (amount == 0) amount = 1e18;

        vm.prank(whale);
        require(IERC20(asset).transfer(address(this), amount), "fund transfer failed");

        console.log("asset before", IERC20(asset).balanceOf(address(this)));
        console.log("aToken before", IERC20(aToken).balanceOf(address(this)));

        AaveStrategy aaveStrategy = new AaveStrategy();
        bytes memory data = abi.encodeWithSelector(
            AaveStrategy.deposit.selector,
            IPool(aavePool),
            IERC20(aToken),
            IERC20(asset),
            amount
        );
        (bool ok, bytes memory ret) = address(aaveStrategy).delegatecall(data);
        console.log("delegatecall ok", ok);
        if (ok) {
            uint256 minted = abi.decode(ret, (uint256));
            console.log("minted aToken", minted);
        } else {
            console.logBytes(ret);
        }

        console.log("asset after", IERC20(asset).balanceOf(address(this)));
        console.log("aToken after", IERC20(aToken).balanceOf(address(this)));
    }
}

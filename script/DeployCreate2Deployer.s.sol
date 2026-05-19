// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Create2Deployer} from "../src/helpers/Create2Deployer.sol";

contract DeployCreate2Deployer is Script {
    function run() external {
        vm.startBroadcast();
        Create2Deployer deployer = new Create2Deployer();
        console2.log("Create2Deployer deployed at:", address(deployer));
        vm.stopBroadcast();
    }
}

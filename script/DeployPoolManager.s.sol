// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PoolManager} from "../src/managers/PoolManager.sol";
import {Script} from "forge-std/Script.sol";

contract DeployPoolManager is Script {
    function setUp() public {}

    function run() public returns (PoolManager deployed) {
        vm.startBroadcast();
        deployed = new PoolManager(msg.sender); // Pass deployer as initialOwner
        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployTokens is Script {
    function run() external {
        vm.startBroadcast();
        // Deploy two example tokens; adjust names/symbols as needed
        ERC20PresetMinterPauser token0 = new ERC20PresetMinterPauser("Token0", "TK0");
        ERC20PresetMinterPauser token1 = new ERC20PresetMinterPauser("Token1", "TK1");
        vm.stopBroadcast();
        console2.log("Token0 address:", address(token0));
        console2.log("Token1 address:", address(token1));
    }
}

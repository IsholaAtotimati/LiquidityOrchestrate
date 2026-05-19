// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/// @notice Base contract to expose Chainlink automation hooks while delegating implementation details.
abstract contract ChainlinkAutomation is AutomationCompatibleInterface {
    function checkUpkeep(bytes calldata performData) external view override returns (bool upkeepNeeded, bytes memory) {
        return _checkUpkeep(performData);
    }

    function performUpkeep(bytes calldata performData) external override {
        _performUpkeep(performData);
    }

    function _checkUpkeep(bytes calldata data) internal view virtual returns (bool upkeepNeeded, bytes memory performData);
    function _performUpkeep(bytes calldata performData) internal virtual;
}

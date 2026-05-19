// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal TestUnlocker used for test builds when upstream test helper is absent
contract TestUnlocker {
	function unlockCallback(bytes calldata) external returns (bytes memory) {
		return "";
	}
}

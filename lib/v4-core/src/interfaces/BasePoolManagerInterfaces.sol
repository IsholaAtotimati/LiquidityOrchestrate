// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../types/Currency.sol";
import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

/// @notice Interface for all protocol-fee related functions in the pool manager
interface IProtocolFees {
    error ProtocolFeeTooLarge(uint24 fee);
    error InvalidCaller();
    error ProtocolFeeCurrencySynced();
    event ProtocolFeeControllerUpdated(address indexed protocolFeeController);
    event ProtocolFeeUpdated(PoolId indexed id, uint24 protocolFee);
    function protocolFeesAccrued(Currency currency) external view returns (uint256 amount);
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external;
    function setProtocolFeeController(address controller) external;
    function collectProtocolFees(address recipient, Currency currency, uint256 amount) external returns (uint256 amountCollected);
    function protocolFeeController() external view returns (address);
}

/// @notice Interface for claims over a contract balance, wrapped as a ERC6909
interface IERC6909Claims {
    event OperatorSet(address indexed owner, address indexed operator, bool approved);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id, uint256 amount);
    event Transfer(address caller, address indexed from, address indexed to, uint256 indexed id, uint256 amount);
    function balanceOf(address owner, uint256 id) external view returns (uint256 amount);
    function allowance(address owner, address spender, uint256 id) external view returns (uint256 amount);
    function isOperator(address owner, address spender) external view returns (bool approved);
    function transfer(address receiver, uint256 id, uint256 amount) external returns (bool);
    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) external returns (bool);
    function approve(address spender, uint256 id, uint256 amount) external returns (bool);
    function setOperator(address operator, bool approved) external returns (bool);
}

/// @notice Interface for functions to access any storage slot in a contract
interface IExtsload {
    function extsload(bytes32 slot) external view returns (bytes32 value);
    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values);
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values);
}

/// @notice Interface for functions to access any transient storage slot in a contract
interface IExttload {
    function exttload(bytes32 slot) external view returns (bytes32 value);
    function exttload(bytes32[] calldata slots) external view returns (bytes32[] memory values);
}

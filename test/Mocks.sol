// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name; symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "BAL");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount; return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "BAL");
        require(allowance[from][msg.sender] >= amount, "ALLOW");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockAavePool {
    address public aToken;
    MockERC20 public assetToken;
    MockERC20 public aTokenContract;

    constructor(address _aToken, address _asset) {
        aToken = _aToken;
        aTokenContract = MockERC20(_aToken);
        assetToken = MockERC20(_asset);
    }

    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        // transfer underlying from msg.sender into the pool, then mint aTokens
        require(assetToken.transferFrom(msg.sender, address(this), amount), "TRANSFER_FAILED");
        aTokenContract.mint(onBehalfOf, amount);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        // burn aTokens from msg.sender and return underlying from the pool to `to`
        require(aTokenContract.transferFrom(msg.sender, address(this), amount), "TRANSFER_FAILED");
        require(assetToken.transfer(to, amount), "TRANSFER_FAILED");
        return amount;
    }

    // stubs for other IPool functions (not used in tests)
    fallback() external payable {}
    receive() external payable {}
}

contract MockERC4626 {
    MockERC20 public asset;
    mapping(address => uint256) internal _shares;

    constructor(address _asset) {
        asset = MockERC20(_asset);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        // mint vault shares equal to assets
        _shares[receiver] += assets;
        return assets;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256) {
        // mint assets to receiver
        asset.mint(receiver, shares);
        return shares;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares;
    }

    function balanceOf(address who) external view returns (uint256) {
        return _shares[who];
    }
}

contract MockAggregator {
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId = 1;

    bool public doRevert = false;

    function set(int256 _answer, uint256 _updatedAt) external {
        answer = _answer;
        updatedAt = _updatedAt;
        roundId += 1;
    }

    function setRevert(bool v) external { doRevert = v; }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (doRevert) revert("feed revert");
        return (roundId, answer, 0, updatedAt, roundId);
    }
}

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

contract MockPoolManager {
    function callRegister(address hook, PoolId pid, address lp, uint128 l0, uint128 l1, int24 lower, int24 upper) external {
        (bool ok, ) = hook.call(abi.encodeWithSignature("registerPosition(bytes32,address,uint128,uint128,int24,int24)", PoolId.unwrap(pid), lp, l0, l1, lower, upper));
        require(ok, "register failed");
    }

    function extsload(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }
}


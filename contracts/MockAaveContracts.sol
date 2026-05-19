// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockAToken {
    string public name = "Mock aToken";
    string public symbol = "aMOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

contract MockPriceFeed {
    int256 public answer = 1e8; // 1 USD with 8 decimals
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public roundId = 1;

    bool public doRevert = false;

    function setPrice(int256 _answer, uint256 _updatedAt) external {
        answer = _answer;
        updatedAt = _updatedAt;
        roundId += 1;
    }

    function setRevert(bool v) external {
        doRevert = v;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        if (doRevert) revert("feed revert");
        return (roundId, answer, startedAt, updatedAt, roundId);
    }
}

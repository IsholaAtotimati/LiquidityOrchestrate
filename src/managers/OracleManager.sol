// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

library OracleManager {
    uint256 internal constant ORACLE_MAX_DELAY = 1 hours;
    uint256 internal constant MAX_DEVIATION_BP = 500; // 5%
    uint256 internal constant BP = 10000;

    /// @notice Fetch safe price from Chainlink
    function getSafePrice(
        mapping(address => AggregatorV3Interface) storage feeds,
        address asset
    ) internal view returns (int256 price) {
        AggregatorV3Interface feed = feeds[asset];
        require(address(feed) != address(0), "NO_FEED");

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        require(answer > 0, "BAD_PRICE");
        require(updatedAt <= block.timestamp, "FUTURE_PRICE");
        require(block.timestamp - updatedAt <= ORACLE_MAX_DELAY, "STALE_PRICE");

        // critical Chainlink safety check
        require(answeredInRound >= roundId, "INCOMPLETE_ROUND");

        return answer;
    }

    /// @notice Non-reverting safe getter for Chainlink prices.
    /// @dev Returns (ok, price). Does not revert on missing feed or stale/bad data.
    function safeGetPrice(
        mapping(address => AggregatorV3Interface) storage feeds,
        address asset
    ) internal view returns (bool ok, int256 price) {
        AggregatorV3Interface feed = feeds[asset];
        if (address(feed) == address(0)) return (false, 0);

        try feed.latestRoundData() returns (uint80 roundId, int256 answer, uint256 /*startedAt*/, uint256 updatedAt, uint80 answeredInRound) {
            if (answer <= 0) return (false, 0);
            if (updatedAt > block.timestamp) return (false, 0);
            if (block.timestamp - updatedAt > ORACLE_MAX_DELAY) return (false, 0);
            if (answeredInRound < roundId) return (false, 0);
            return (true, answer);
        } catch {
            return (false, 0);
        }
    }

    /// @notice Normalize price to 1e18 precision
    function normalizePrice(
        int256 price,
        uint8 decimals
    ) internal pure returns (uint256) {
        require(price > 0, "INVALID_PRICE");

        if (decimals == 18) return uint256(price);

        if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        }

        return uint256(price) / (10 ** (decimals - 18));
    }

    /// @notice Check price deviation vs reference
    function checkDeviation(
        int256 current,
        int256 refPrice
    ) internal pure {
        if (refPrice == 0) return;

        int256 diff = current > refPrice
            ? current - refPrice
            : refPrice - current;

        require(
            (uint256(diff) * BP) / uint256(refPrice) <= MAX_DEVIATION_BP,
            "PRICE_DEVIATION"
        );
    }
}
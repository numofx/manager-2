// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../../../oracles/mento/ISortedOracles.sol";

/**
 * @title SortedOraclesMock
 * @notice Mock implementation of Mento's SortedOracles for testing
 */
contract SortedOraclesMock is ISortedOracles {
    struct RateData {
        uint256 rateNumerator;
        uint256 rateDenominator;
        uint256 timestamp;
        uint256 numRates;
    }

    mapping(address => RateData) private rates;

    /**
     * @notice Set the median rate for a feed (simplified mock)
     * @param rateFeedID The rate feed identifier
     * @param rateNumerator The rate numerator (e.g., USD per KES in 1e24 units)
     */
    function setMedianRate(address rateFeedID, uint256 rateNumerator) external {
        rates[rateFeedID] = RateData({
            rateNumerator: rateNumerator,
            rateDenominator: 1e24, // Fixed denominator for Fixidity
            timestamp: block.timestamp,
            numRates: 5 // Mock: assume 5 oracles reported
        });
    }

    /**
     * @notice Set the median rate with a custom timestamp
     * @param rateFeedID The rate feed identifier
     * @param rateNumerator The rate numerator
     * @param timestamp Custom timestamp for staleness testing
     */
    function setMedianRate(address rateFeedID, uint256 rateNumerator, uint256 timestamp) external {
        rates[rateFeedID] = RateData({
            rateNumerator: rateNumerator,
            rateDenominator: 1e24,
            timestamp: timestamp,
            numRates: 5
        });
    }

    /**
     * @notice Set the median rate with custom denominator (for testing edge cases)
     * @param rateFeedID The rate feed identifier
     * @param rateNumerator The rate numerator
     * @param rateDenominator The rate denominator (normally 1e24)
     * @param timestamp Custom timestamp
     */
    function setMedianRateWithDenominator(
        address rateFeedID,
        uint256 rateNumerator,
        uint256 rateDenominator,
        uint256 timestamp
    ) external {
        rates[rateFeedID] = RateData({
            rateNumerator: rateNumerator,
            rateDenominator: rateDenominator,
            timestamp: timestamp,
            numRates: 5
        });
    }

    // ========== ISortedOracles Implementation ==========

    function medianRate(address rateFeedID)
        external
        view
        override
        returns (uint256 rateNumerator, uint256 rateDenominator)
    {
        RateData memory data = rates[rateFeedID];
        return (data.rateNumerator, data.rateDenominator);
    }

    function medianTimestamp(address rateFeedID) external view override returns (uint256 timestamp) {
        return rates[rateFeedID].timestamp;
    }

    function numRates(address rateFeedID) external view override returns (uint256 count) {
        return rates[rateFeedID].numRates;
    }

    /**
     * @notice Helper to set the number of rates (for testing conditions that require minimum reporters)
     */
    function setNumRates(address rateFeedID, uint256 count) external {
        rates[rateFeedID].numRates = count;
    }
}

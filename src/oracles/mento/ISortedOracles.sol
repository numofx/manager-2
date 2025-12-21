// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

/**
 * @title ISortedOracles
 * @notice Interface for Mento's SortedOracles contract on Celo
 * @dev Mento maintains sorted price reports from multiple oracles and returns the median
 *
 * Celo Mainnet Address: 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33
 * KES/USD Feed ID: 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169
 *
 * Price Direction: Mento returns USD per 1 unit of asset (quote per base)
 * Precision: All rates use 1e24 fixed-point precision
 */
interface ISortedOracles {
    /**
     * @notice Get the median exchange rate for a rate feed (Fixidity format)
     * @param rateFeedID The address identifier of the rate feed
     * @return rateNumerator The rate numerator (e.g., USD per KES in 1e24 units)
     * @return rateDenominator The fixed denominator (always 1e24 for Fixidity)
     * @dev Returns a Fixidity fraction: actualRate = rateNumerator / rateDenominator
     *      For KES/USD feed: USD_per_KES = rateNumerator / 1e24
     *      Example: If 1 KES = 0.007757 USD, returns (7.757e21, 1e24)
     */
    function medianRate(address rateFeedID) external view returns (uint256 rateNumerator, uint256 rateDenominator);

    /**
     * @notice Get the number of rates currently stored for a rate feed
     * @param rateFeedID The rate feed identifier
     * @return count Number of rates in the sorted list
     */
    function numRates(address rateFeedID) external view returns (uint256 count);

    /**
     * @notice Get the median timestamp across all reports for a rate feed
     * @param rateFeedID The rate feed identifier
     * @return timestamp The median timestamp of all reports (Unix timestamp in seconds)
     * @dev Use this for staleness checks, NOT the second return value of medianRate
     */
    function medianTimestamp(address rateFeedID) external view returns (uint256 timestamp);
}

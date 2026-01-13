// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "../../interfaces/IOracle.sol";
import "./ISortedOracles.sol";

/**
 * @title MentoSpotOracle
 * @notice Oracle adapter for Mento protocol's SortedOracles
 * @dev Returns cKES per USDT (≈ cKES/USD) in 1e18 precision
 *
 * CRITICAL INVERSION LOGIC:
 * - Mento KES/USD feed returns: USD per 1 KES in 1e24 precision
 * - Yield Protocol needs: cKES per 1 USDT in 1e18 precision (for collateral valuation)
 * - This oracle INVERTS the Mento rate: cKES/USD = 1 / (USD/KES)
 *
 * Example:
 * - Mento returns: 0.0073 USD per 1 KES (7.3e21 in 1e24)
 * - Oracle returns: 137 cKES per 1 USD (137e18 in 1e18)
 * - Usage: 100 USDT collateral = 100 * 137 = 13,700 cKES equivalent value
 *
 * Security Features:
 * - Staleness check: maxAge = 3600 seconds (1 hour)
 * - Sanity bounds: Rejects prices outside [min, max] range
 * - Access control: Only authorized addresses can configure
 */
contract MentoSpotOracle is IOracle, AccessControl {
    using Cast for bytes32;
    using Math for uint256;

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address indexed rateFeedID,
        uint256 maxAge
    );
    event BoundsSet(bytes6 indexed baseId, bytes6 indexed quoteId, uint256 minPrice, uint256 maxPrice);

    /// @dev Mento uses 24 decimal places for rate precision
    uint256 private constant MENTO_DECIMALS = 24;

    /// @dev Standard DeFi precision (18 decimals)
    uint256 private constant TARGET_DECIMALS = 18;

    /// @dev Scale factor for inversion: 1e42 = 1e24 * 1e18
    uint256 private constant INVERSION_SCALE = 1e42;

    /// @dev Mento SortedOracles contract instance
    ISortedOracles public immutable sortedOracles;

    struct Source {
        address rateFeedID;      // Mento rate feed identifier (e.g., KES/USD feed)
        uint256 maxAge;          // Maximum age in seconds for a valid price
        uint256 minPrice;        // Minimum acceptable price in 1e18 (0 = no check)
        uint256 maxPrice;        // Maximum acceptable price in 1e18 (0 = no check)
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /**
     * @notice Construct the MentoSpotOracle
     * @param sortedOracles_ Address of Mento's SortedOracles contract
     */
    constructor(ISortedOracles sortedOracles_) {
        require(address(sortedOracles_) != address(0), "Invalid SortedOracles address");
        sortedOracles = sortedOracles_;
    }

    /**
     * @notice Create a price source
     * @param baseId Yield protocol identifier for base asset (e.g., "cKES")
     * @param quoteId Yield protocol identifier for quote asset (e.g., "USDT")
     * @param rateFeedID Mento rate feed identifier (e.g., 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169 for KES/USD)
     * @param maxAge Maximum age in seconds (e.g., 3600 for 1 hour)
     * @dev This oracle will INVERT the Mento rate to return base-per-quote.
     */
    function addSource(
        bytes6 baseId,
        bytes6 quoteId,
        address rateFeedID,
        uint256 maxAge
    ) external auth {
        require(rateFeedID != address(0), "Invalid rateFeedID");
        require(maxAge > 0, "maxAge must be > 0");
        require(sources[baseId][quoteId].rateFeedID == address(0), "Source already set");

        sources[baseId][quoteId] = Source({
            rateFeedID: rateFeedID,
            maxAge: maxAge,
            minPrice: 0,    // No minimum bound by default
            maxPrice: 0     // No maximum bound by default
        });

        emit SourceSet(baseId, quoteId, rateFeedID, maxAge);
    }

    /**
     * @notice Update a price source
     * @param baseId Yield protocol identifier for base asset (e.g., "cKES")
     * @param quoteId Yield protocol identifier for quote asset (e.g., "USDT")
     * @param rateFeedID Mento rate feed identifier (e.g., 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169 for KES/USD)
     * @param maxAge Maximum age in seconds (e.g., 3600 for 1 hour)
     * @dev This oracle will INVERT the Mento rate to return base-per-quote.
     *      Existing sanity bounds are preserved when updating a source.
     */
    function setSource(
        bytes6 baseId,
        bytes6 quoteId,
        address rateFeedID,
        uint256 maxAge
    ) external auth {
        require(rateFeedID != address(0), "Invalid rateFeedID");
        require(maxAge > 0, "maxAge must be > 0");

        Source storage existing = sources[baseId][quoteId];
        require(existing.rateFeedID != address(0), "Source not found");
        existing.rateFeedID = rateFeedID;
        existing.maxAge = maxAge;

        emit SourceSet(baseId, quoteId, rateFeedID, maxAge);
    }

    /**
     * @notice Set sanity bounds for a price source
     * @param baseId Base asset identifier
     * @param quoteId Quote asset identifier
     * @param minPrice Minimum acceptable price in 1e18 precision (0 to disable)
     * @param maxPrice Maximum acceptable price in 1e18 precision (0 to disable)
     * @dev Bounds are for the INVERTED price (cKES per USD)
     *      If Mento USD/cKES range is [$0.005, $0.015], then cKES/USD range is [66.67, 200]
     *      In 1e18: minPrice = 66.67e18, maxPrice = 200e18
     */
    function setBounds(bytes6 baseId, bytes6 quoteId, uint256 minPrice, uint256 maxPrice) external auth {
        require(sources[baseId][quoteId].rateFeedID != address(0), "Source not found");
        if (minPrice > 0 && maxPrice > 0) {
            require(minPrice < maxPrice, "Invalid bounds");
        }
        sources[baseId][quoteId].minPrice = minPrice;
        sources[baseId][quoteId].maxPrice = maxPrice;
        emit BoundsSet(baseId, quoteId, minPrice, maxPrice);
    }

    /**
     * @notice Peek at the latest oracle price without state changes
     * @param base Base asset identifier (e.g., cKES)
     * @param quote Quote asset identifier (e.g., USDT)
     * @param amount Amount of quote asset (USDT) to convert
     * @return value Equivalent amount in base asset (cKES), in 1e18 precision
     * @return updateTime Timestamp when the price was last updated
     * @dev Returns cKES per USDT (≈ cKES/USD), scaled to 1e18
     * @dev CRITICAL: This is a view function - no state changes
     */
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount);
    }

    /**
     * @notice Get the latest oracle price (same as peek for this oracle)
     * @param base Base asset identifier (e.g., cKES)
     * @param quote Quote asset identifier (e.g., USDT)
     * @param amount Amount of quote asset (USDT) to convert
     * @return value Equivalent amount in base asset (cKES), in 1e18 precision
     * @return updateTime Timestamp when the price was last updated
     * @dev Returns cKES per USDT (≈ cKES/USD), scaled to 1e18
     */
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount);
    }

    /**
     * @notice Internal function to fetch and convert prices from Mento
     * @param baseId Base asset identifier (bytes6)
     * @param quoteId Quote asset identifier (bytes6)
     * @param amount Amount to convert (quote asset, e.g., USDT amount)
     * @return value Converted amount (base asset, e.g., cKES equivalent)
     * @return updateTime Price timestamp
     * @dev INVERSION LOGIC:
     *      1. Fetch Mento rate: USD per KES (1e24)
     *      2. Convert to 1e18: rate18 = mentoRate / 1e6
     *      3. Invert: cKES_per_USD = 1e42 / mentoRate
     *      4. Apply to amount: value = (amount * cKES_per_USD) / 1e18
     */
    function _peek(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amount
    ) private view returns (uint256 value, uint256 updateTime) {
        // Handle same-asset conversion
        if (baseId == quoteId) {
            return (amount, block.timestamp);
        }

        Source memory source = sources[baseId][quoteId];
        require(source.rateFeedID != address(0), "Source not found");

        // Fetch median rate from Mento SortedOracles (Fixidity format)
        uint256 rateNumerator;
        uint256 rateDenominator;
        (rateNumerator, rateDenominator) = sortedOracles.medianRate(source.rateFeedID);

        // Validate rate
        require(rateNumerator > 0, "Invalid Mento rate: zero");
        require(rateDenominator == 1e24, "Unexpected Mento denominator");

        // Check staleness using separate timestamp function
        updateTime = sortedOracles.medianTimestamp(source.rateFeedID);
        require(updateTime <= block.timestamp, "Future timestamp");
        require(block.timestamp - updateTime <= source.maxAge, "Stale price");

        // ========== INVERSION: Convert USD/KES to cKES/USD ==========
        // Mento returns: rateNumerator / rateDenominator = USD per 1 KES
        // We need: cKES per 1 USD in 1e18
        //
        // Formula: cKES_per_USD = (1e18 * rateDenominator) / rateNumerator = 1e42 / rateNumerator
        //
        // Example (verified on-chain 2024-12-21):
        // - rateNumerator = 7.757e21
        // - rateDenominator = 1e24
        // - USD_per_KES = 7.757e21 / 1e24 = 0.007757
        // - invertedRate = 1e42 / 7.757e21 ≈ 128.92e18 (128.92 cKES per USD)
        //
        // Division is safe: rateNumerator > 0 (checked above)
        uint256 invertedRate = INVERSION_SCALE / rateNumerator;

        // ========== SANITY BOUNDS ==========
        // Bounds are for inverted price (cKES per USD, 1e18)
        if (source.minPrice > 0) {
            require(invertedRate >= source.minPrice, "Price below minimum");
        }
        if (source.maxPrice > 0) {
            require(invertedRate <= source.maxPrice, "Price above maximum");
        }

        // ========== AMOUNT CONVERSION ==========
        // Convert quote amount (USDT) to base equivalent (cKES)
        // Formula: value = (amount * rate) / 1e18
        //
        // Example: 100 USDT at 137 cKES/USD
        // - amount = 100e18 (100 USDT in 18 decimals)
        // - invertedRate = 137e18
        // - value = (100e18 * 137e18) / 1e18 = 13700e18 (13,700 cKES)
        value = (amount * invertedRate) / 1e18;
    }
}

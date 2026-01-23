// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "../../interfaces/IOracle.sol";
import "../../interfaces/ILiquidationOracle.sol";
import "../../interfaces/IRiskOracle.sol";
import "../chainlink/AggregatorV3Interface.sol";
import "./ISortedOracles.sol";

/**
 * @title MentoSpotOracle
 * @notice Oracle adapter for Mento protocol's SortedOracles
 * @dev Returns KESm per USDT (≈ KESm/USD) in 1e18 precision
 *
 * CRITICAL INVERSION LOGIC:
 * - Mento KES/USD feed returns: USD per 1 KES in 1e24 precision
 * - Yield Protocol needs: KESm per 1 USDT in 1e18 precision (for collateral valuation)
 * - This oracle INVERTS the Mento rate: KESm_per_USD = 1e42 / rateNumerator
 *
 * Example:
 * - rateNumerator = 7.3e21, rateDenominator = 1e24 (USD per KES = 7.3e21 / 1e24)
 * - Oracle returns: 1e42 / rateNumerator ≈ 137e18 KESm per USD
 * - Usage: 100 USDT collateral = 100 * 137 = 13,700 KESm equivalent value
 *
 * Security Features:
 * - Staleness check: maxAge = 3600 seconds (1 hour)
 * - Sanity bounds: Rejects prices outside [min, max] range
 * - Access control: Only authorized addresses can configure
 */
contract MentoSpotOracle is IOracle, ILiquidationOracle, IRiskOracle, AccessControl {
    using Cast for bytes32;
    using Math for uint256;

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address indexed rateFeedID,
        uint256 maxAge,
        uint256 minNumRates
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
    AggregatorV3Interface public immutable usdtUsdFeed;

    uint32 public maxAge = 3600;
    uint256 public mintBandLo = 0.90e18;
    uint256 public mintBandHi = 1.10e18;
    uint256 public riskOffLo = 0.97e18;
    uint256 public riskOffHi = 1.03e18;

    bool public riskOff;
    uint80 public lastRoundId;

    enum Use {
        MINT,
        LIQUIDATION
    }

    struct Source {
        address rateFeedID;      // Mento rate feed identifier (e.g., KES/USD feed)
        uint256 maxAge;          // Maximum age in seconds for a valid price
        uint256 minPrice;        // Minimum acceptable price in 1e18 (0 = no check)
        uint256 maxPrice;        // Maximum acceptable price in 1e18 (0 = no check)
        uint256 minNumRates;     // Minimum number of reports required (0 = no check)
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    /**
     * @notice Construct the MentoSpotOracle
     * @param sortedOracles_ Address of Mento's SortedOracles contract
     */
    constructor(ISortedOracles sortedOracles_, AggregatorV3Interface usdtUsdFeed_) {
        require(address(sortedOracles_) != address(0), "Invalid SortedOracles address");
        require(address(usdtUsdFeed_) != address(0), "Invalid USDT/USD feed");
        sortedOracles = sortedOracles_;
        usdtUsdFeed = usdtUsdFeed_;
    }

    /**
     * @notice Create a price source
     * @param baseId Yield protocol identifier for base asset (e.g., "KESm")
     * @param quoteId Yield protocol identifier for quote asset (e.g., "USDT")
     * @param rateFeedID Mento rate feed identifier (e.g., 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169 for KES/USD)
     * @param maxAge_ Maximum age in seconds (e.g., 3600 for 1 hour)
     * @param minNumRates Minimum number of oracle reports required (0 to disable)
     * @dev This oracle will INVERT the Mento rate to return base-per-quote.
     */
    function addSource(
        bytes6 baseId,
        bytes6 quoteId,
        address rateFeedID,
        uint256 maxAge_,
        uint256 minNumRates
    ) external auth {
        require(rateFeedID != address(0), "Invalid rateFeedID");
        require(maxAge_ > 0, "maxAge must be > 0");
        require(sources[baseId][quoteId].rateFeedID == address(0), "Source already set");

        sources[baseId][quoteId] = Source({
            rateFeedID: rateFeedID,
            maxAge: maxAge_,
            minPrice: 0,    // No minimum bound by default
            maxPrice: 0,    // No maximum bound by default
            minNumRates: minNumRates
        });

        emit SourceSet(baseId, quoteId, rateFeedID, maxAge_, minNumRates);
    }

    /**
     * @notice Update a price source
     * @param baseId Yield protocol identifier for base asset (e.g., "KESm")
     * @param quoteId Yield protocol identifier for quote asset (e.g., "USDT")
     * @param rateFeedID Mento rate feed identifier (e.g., 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169 for KES/USD)
     * @param maxAge_ Maximum age in seconds (e.g., 3600 for 1 hour)
     * @param minNumRates Minimum number of oracle reports required (0 to disable)
     * @dev This oracle will INVERT the Mento rate to return base-per-quote.
     *      Existing sanity bounds are preserved when updating a source.
     */
    function setSource(
        bytes6 baseId,
        bytes6 quoteId,
        address rateFeedID,
        uint256 maxAge_,
        uint256 minNumRates
    ) external auth {
        require(rateFeedID != address(0), "Invalid rateFeedID");
        require(maxAge_ > 0, "maxAge must be > 0");

        Source storage existing = sources[baseId][quoteId];
        require(existing.rateFeedID != address(0), "Source not found");
        existing.rateFeedID = rateFeedID;
        existing.maxAge = maxAge_;
        existing.minNumRates = minNumRates;

        emit SourceSet(baseId, quoteId, rateFeedID, maxAge_, minNumRates);
    }

    /**
     * @notice Set sanity bounds for a price source
     * @param baseId Base asset identifier
     * @param quoteId Quote asset identifier
     * @param minPrice Minimum acceptable price in 1e18 precision (0 to disable)
     * @param maxPrice Maximum acceptable price in 1e18 precision (0 to disable)
     * @dev Bounds are for the INVERTED price (KESm per USD)
     *      If Mento USD/KESm range is [$0.005, $0.015], then KESm/USD range is [66.67, 200]
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
     * @param base Base asset identifier (e.g., KESm)
     * @param quote Quote asset identifier (e.g., USDT)
     * @param amount Amount of quote asset (USDT) to convert, in WAD (1e18)
     * @return value Equivalent amount in base asset (KESm), in 1e18 precision
     * @return updateTime Timestamp when the price was last updated
     * @dev Returns KESm per USDT (≈ KESm/USD), scaled to 1e18
     * @dev CRITICAL: This is a view function - no state changes
     */
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount, Use.MINT);
    }

    /**
     * @notice Get the latest oracle price (same as peek for this oracle)
     * @param base Base asset identifier (e.g., KESm)
     * @param quote Quote asset identifier (e.g., USDT)
     * @param amount Amount of quote asset (USDT) to convert, in WAD (1e18)
     * @return value Equivalent amount in base asset (KESm), in 1e18 precision
     * @return updateTime Timestamp when the price was last updated
     * @dev Returns KESm per USDT (≈ KESm/USD), scaled to 1e18
     */
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount, Use.MINT);
    }

    function peekLiquidation(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount, Use.LIQUIDATION);
    }

    function getLiquidation(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external virtual override returns (uint256 value, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), amount, Use.LIQUIDATION);
    }

    function updateRiskOff() external override {
        (bool ok, uint256 spot, uint80 roundId,) = _readUsdtUsdSpot1e18();

        if (!ok) {
            riskOff = true;
            return;
        }

        if (roundId == lastRoundId) return;
        lastRoundId = roundId;

        uint256 peg = 1e18;
        uint256 diff = spot > peg ? spot - peg : peg - spot;
        uint256 allowed = spot >= peg
            ? (riskOffHi > peg ? riskOffHi - peg : 0)
            : (peg > riskOffLo ? peg - riskOffLo : 0);

        if (diff <= allowed) {
            riskOff = false;
        } else {
            riskOff = true;
        }
    }

    /**
     * @notice Internal function to fetch and convert prices from Mento
     * @param baseId Base asset identifier (bytes6)
     * @param quoteId Quote asset identifier (bytes6)
     * @param amount Amount to convert (quote asset, e.g., USDT amount), in WAD (1e18)
     * @return value Converted amount (base asset, e.g., KESm equivalent)
     * @return updateTime Price timestamp
     * @dev INVERSION LOGIC:
     *      1. Fetch Mento rate: USD per KES (Fixidity, denominator = 1e24)
     *      2. Invert using full precision:
     *         KESm_per_USD = (1e18 * 1e24) / rateNumerator = 1e42 / rateNumerator
     *      3. Apply to amount:
     *         value = (amount * KESm_per_USD) / 1e18
     */
    function _peek(
        bytes6 baseId,
        bytes6 quoteId,
        uint256 amount,
        Use use
    ) private view returns (uint256 value, uint256 updateTime) {
        // Handle same-asset conversion
        if (baseId == quoteId) {
            return (amount, block.timestamp);
        }

        Source memory source = sources[baseId][quoteId];
        require(source.rateFeedID != address(0), "Source not found");

        // Enforce minimum report count when configured
        if (source.minNumRates != 0) {
            require(
                sortedOracles.numRates(source.rateFeedID) >= source.minNumRates,
                "Insufficient oracle reports"
            );
        }

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

        // ========== INVERSION: Convert USD/KES to KESm/USD ==========
        // Mento returns: rateNumerator / rateDenominator = USD per 1 KES
        // We need: KESm per 1 USD in 1e18
        //
        // Formula: KESm_per_USD = (1e18 * rateDenominator) / rateNumerator = 1e42 / rateNumerator
        //
        // Example (verified on-chain 2024-12-21):
        // - rateNumerator = 7.757e21
        // - rateDenominator = 1e24
        // - USD_per_KES = 7.757e21 / 1e24 = 0.007757
        // - invertedRate = 1e42 / 7.757e21 ≈ 128.92e18 (128.92 KESm per USD)
        //
        // Division is safe: rateNumerator > 0 (checked above)
        uint256 invertedRate = INVERSION_SCALE / rateNumerator;

        // ========== SANITY BOUNDS ==========
        // Bounds are for inverted price (KESm per USD, 1e18)
        if (source.minPrice > 0) {
            require(invertedRate >= source.minPrice, "Price below minimum");
        }
        if (source.maxPrice > 0) {
            require(invertedRate <= source.maxPrice, "Price above maximum");
        }

        (uint256 usdtUsd, , uint256 usdtUpdatedAt) = _usdtUsd1e18(use);

        // ========== AMOUNT CONVERSION ==========
        // Convert quote amount (USDT) to base equivalent (KESm)
        // Formula: value = (amount * rate) / 1e18
        //
        // Example: 100 USDT with rateNumerator = 7.3e21 (rateDenominator = 1e24)
        // - amount = 100e18 (100 USDT in 18 decimals)
        // - invertedRate = 1e42 / rateNumerator ≈ 137e18
        // - value = (100e18 * 137e18) / 1e18 = 13700e18 (13,700 KESm)
        value = amount.wmul(invertedRate);
        value = value.wmul(usdtUsd);

        if (usdtUpdatedAt < updateTime) updateTime = usdtUpdatedAt;
    }

    function _readUsdtUsdSpot1e18()
        internal
        view
        returns (bool ok, uint256 spot, uint80 roundId, uint256 updatedAt)
    {
        if (address(usdtUsdFeed) == address(0)) return (false, 0, 0, 0);

        uint80 answeredInRound;
        int256 answer;
        try usdtUsdFeed.latestRoundData() returns (
            uint80 roundId_,
            int256 answer_,
            uint256,
            uint256 updatedAt_,
            uint80 answeredInRound_
        ) {
            roundId = roundId_;
            answer = answer_;
            updatedAt = updatedAt_;
            answeredInRound = answeredInRound_;
        } catch {
            return (false, 0, 0, 0);
        }

        if (answer <= 0) return (false, 0, roundId, updatedAt);
        if (updatedAt == 0) return (false, 0, roundId, updatedAt);
        if (answeredInRound < roundId) return (false, 0, roundId, updatedAt);
        if (updatedAt > block.timestamp) return (false, 0, roundId, updatedAt);
        if (block.timestamp - updatedAt > maxAge) return (false, 0, roundId, updatedAt);

        uint256 scaled = uint256(answer);
        uint8 decimals;
        try usdtUsdFeed.decimals() returns (uint8 decimals_) {
            decimals = decimals_;
        } catch {
            return (false, 0, roundId, updatedAt);
        }
        if (decimals > TARGET_DECIMALS) return (false, 0, roundId, updatedAt);
        if (decimals < TARGET_DECIMALS) {
            scaled *= 10 ** (TARGET_DECIMALS - decimals);
        }

        return (true, scaled, roundId, updatedAt);
    }

    function _usdtUsd1e18(Use use) internal view returns (uint256 spot, uint80 roundId, uint256 updatedAt) {
        bool ok;
        (ok, spot, roundId, updatedAt) = _readUsdtUsdSpot1e18();
        require(ok, "USDT/USD invalid");

        if (use == Use.MINT) {
            require(spot >= mintBandLo && spot <= mintBandHi, "USDT/USD oob mint");
        } else if (spot > 1e18) {
            spot = 1e18;
        }
    }
}

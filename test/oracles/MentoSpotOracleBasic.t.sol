// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { MentoSpotOracle } from "src/oracles/mento/MentoSpotOracle.sol";
import { ISortedOracles } from "src/oracles/mento/ISortedOracles.sol";
import { SortedOraclesMock } from "src/mocks/oracles/mento/SortedOraclesMock.sol";
import { ChainlinkAggregatorV3MockEx } from "src/mocks/oracles/chainlink/ChainlinkAggregatorV3MockEx.sol";
import { AggregatorV3Interface } from "src/oracles/chainlink/AggregatorV3Interface.sol";

/**
 * @title MentoSpotOracleBasicTest
 * @notice Basic tests for MentoSpotOracle focused on verifying the staleness bug fix
 * @dev Tests the critical fix: using medianTimestamp() instead of medianRate()'s second return value
 */
contract MentoSpotOracleBasicTest is Test {
    MentoSpotOracle public oracle;
    SortedOraclesMock public sortedOraclesMock;
    ChainlinkAggregatorV3MockEx public usdtUsdAggregator;

    // Asset identifiers
    bytes6 public constant KESM_ID = 0x634B45530000; // "KESm"
    bytes6 public constant USDT_ID = 0x555344540000; // "USDT"

    // Mento feed ID (from Celo mainnet)
    address public constant KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;
    address public constant KES_USD_FEED_ALT = address(0xBEEF);

    // Test parameters
    uint256 public constant MAX_AGE = 3600; // 1 hour
    uint256 public constant MIN_PRICE = 66.67e18; // Min KESm per USD
    uint256 public constant MAX_PRICE = 200e18;   // Max KESm per USD
    uint256 public constant MIN_NUM_RATES = 0;

    function setUp() public {
        // Deploy mock
        sortedOraclesMock = new SortedOraclesMock();
        usdtUsdAggregator = new ChainlinkAggregatorV3MockEx(8);

        // Deploy oracle
        oracle = new MentoSpotOracle(
            ISortedOracles(address(sortedOraclesMock)),
            AggregatorV3Interface(address(usdtUsdAggregator))
        );

        // Grant permissions
        oracle.grantRole(oracle.addSource.selector, address(this));
        oracle.grantRole(oracle.setSource.selector, address(this));
        oracle.grantRole(oracle.setBounds.selector, address(this));

        // Configure oracle source (maxAge is set here)
        oracle.addSource(USDT_ID, KESM_ID, KES_USD_FEED, MAX_AGE, MIN_NUM_RATES);

        // Set price bounds separately
        oracle.setBounds(USDT_ID, KESM_ID, MIN_PRICE, MAX_PRICE);

        usdtUsdAggregator.set(100_000_000);

        // Set initial rate: 7.757e21 / 1e24 = 0.007757 USD per KES
        // Inverted: 1e42 / 7.757e21 = 128.92e18 KESm per USD
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21);
    }

    function testSourceDirectionMatchesCauldronConvention() public {
        (address feed,,,,) = oracle.sources(USDT_ID, KESM_ID);
        assertEq(feed, KES_USD_FEED, "Expected source at [USDT][KESm]");
    }

    // ========== Critical Staleness Bug Fix Tests ==========

    /**
     * @notice Test that the oracle correctly uses medianTimestamp() for staleness checks
     * @dev This is the CRITICAL fix - ensures we're not checking against the denominator (1e24)
     */
    function testStalenessUsesMedianTimestamp() public {
        // Set a fresh price
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);

        // Should succeed with fresh timestamp
        (uint256 value, uint256 updateTime) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );

        assertGt(value, 0, "Should return valid value with fresh price");
        assertEq(updateTime, block.timestamp, "Should return correct timestamp");
    }

    /**
     * @notice Test that stale prices are correctly rejected
     * @dev Verifies the staleness check works (wouldn't work if checking against 1e24)
     */
    function testStalePrice() public {
        // Set a stale price (older than MAX_AGE)
        uint256 oldTimestamp = block.timestamp - (MAX_AGE + 1);
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, oldTimestamp);

        // Should revert with "Stale price"
        vm.expectRevert("Stale price");
        oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
    }

    /**
     * @notice Test that future timestamps are rejected
     * @dev Tests the added safety check: require(updateTime <= block.timestamp)
     */
    function testFutureTimestamp() public {
        // Set a future timestamp
        uint256 futureTimestamp = block.timestamp + 1000;
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, futureTimestamp);

        // Should revert with "Future timestamp"
        vm.expectRevert("Future timestamp");
        oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
    }

    /**
     * @notice Test that the denominator is correctly validated
     * @dev Tests the fix: require(rateDenominator == 1e24)
     */
    function testDenominatorValidation() public {
        // Set an incorrect denominator
        sortedOraclesMock.setMedianRateWithDenominator(
            KES_USD_FEED,
            7.757e21,
            1e18, // Wrong denominator!
            block.timestamp
        );

        // Should revert with "Unexpected Mento denominator"
        vm.expectRevert("Unexpected Mento denominator");
        oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
    }

    // ========== Price Inversion Tests ==========

    /**
     * @notice Test correct price inversion
     * @dev Verifies: KESm_per_USD = 1e42 / rateNumerator
     */
    function testPriceInversion() public {
        // Set rate: 7.757e21 (USD per KES in 1e24 precision)
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);

        // Convert 100 USDT to KESm
        (uint256 value,) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );

        // Expected: 100 USDT * (1e42 / 7.757e21) / 1e18
        //         = 100 * 128.92e18 / 1e18
        //         = 12,892e18 KESm
        assertApproxEqRel(value, 12892e18, 0.01e18, "Inverted price should be ~12,892 KESm");
    }

    // ========== Bounds Tests ==========

    /**
     * @notice Test that prices below minimum are rejected
     */
    function testMinPriceBound() public {
        // Set a rate that would give KESm/USD below minimum (66.67e18)
        // If KESm/USD = 50e18, then USD/KES = 1e42 / 50e18 = 20e21
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 20e21, block.timestamp);

        vm.expectRevert("Price below minimum");
        oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
    }

    /**
     * @notice Test that setSource preserves existing sanity bounds
     */
    function testSetSourcePreservesBounds() public {
        oracle.setSource(USDT_ID, KESM_ID, KES_USD_FEED_ALT, MAX_AGE, MIN_NUM_RATES);

        (address rateFeedID, uint256 maxAge, uint256 minPrice, uint256 maxPrice, uint256 minNumRates) =
            oracle.sources(USDT_ID, KESM_ID);

        assertEq(rateFeedID, KES_USD_FEED_ALT, "Rate feed should update");
        assertEq(maxAge, MAX_AGE, "Max age should update");
        assertEq(minPrice, MIN_PRICE, "Min price should be preserved");
        assertEq(maxPrice, MAX_PRICE, "Max price should be preserved");
        assertEq(minNumRates, MIN_NUM_RATES, "Min num rates should update");
    }

    function testSetSourceRevertsIfMissing() public {
        bytes6 OTHER_BASE = bytes6("OTHER");
        vm.expectRevert("Source not found");
        oracle.setSource(OTHER_BASE, KESM_ID, KES_USD_FEED, MAX_AGE, MIN_NUM_RATES);
    }

    function testAddSourceRevertsIfExists() public {
        vm.expectRevert("Source already set");
        oracle.addSource(USDT_ID, KESM_ID, KES_USD_FEED, MAX_AGE, MIN_NUM_RATES);
    }

    // ========== Minimum Reports Tests ==========

    function testMinNumRatesRevertsWhenBelow() public {
        oracle.setSource(USDT_ID, KESM_ID, KES_USD_FEED, MAX_AGE, 2);
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);
        sortedOraclesMock.setNumRates(KES_USD_FEED, 1);

        vm.expectRevert("Insufficient oracle reports");
        oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
    }

    function testMinNumRatesBoundarySucceeds() public {
        oracle.setSource(USDT_ID, KESM_ID, KES_USD_FEED, MAX_AGE, 2);
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);
        sortedOraclesMock.setNumRates(KES_USD_FEED, 2);

        (uint256 value,) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
        assertGt(value, 0, "Should return valid value at minNumRates");
    }

    function testMinNumRatesZeroKeepsLegacyBehavior() public {
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);
        sortedOraclesMock.setNumRates(KES_USD_FEED, 0);

        (uint256 value,) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
        assertGt(value, 0, "Should return value when minNumRates is disabled");
    }

    /**
     * @notice Test that prices above maximum are rejected
     */
    function testMaxPriceBound() public {
        // Set a rate that would give KESm/USD above maximum (200e18)
        // If KESm/USD = 250e18, then USD/KES = 1e42 / 250e18 = 4e21
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 4e21, block.timestamp);

        vm.expectRevert("Price above maximum");
        oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
    }

    // ========== Zero Rate Tests ==========

    /**
     * @notice Test that zero rates are rejected
     */
    function testZeroRate() public {
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 0, block.timestamp);

        vm.expectRevert("Invalid Mento rate: zero");
        oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
    }

    // ========== Integration Test ==========

    /**
     * @notice Full integration test with all safety checks
     */
    function testFullWorkflow() public {
        // Set a valid, fresh price
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);

        // Convert various amounts
        (uint256 value1,) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            1e18 // 1 USDT
        );
        assertApproxEqRel(value1, 128.92e18, 0.01e18, "1 USDT should give ~128.92 KESm");

        (uint256 value2,) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            1000e18 // 1000 USDT
        );
        assertApproxEqRel(value2, 128920e18, 0.01e18, "1000 USDT should give ~128,920 KESm");
    }

    function testMintBandRevertsOnLowUsdtUsd() public {
        usdtUsdAggregator.set(89_000_000);
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);

        vm.expectRevert("USDT/USD oob mint");
        oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
    }

    function testLiquidationCapsPremium() public {
        usdtUsdAggregator.set(105_000_000);
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);

        (uint256 mintValue,) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );
        (uint256 liqValue,) = oracle.peekLiquidation(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            100e18
        );

        uint256 expectedLiq = (mintValue * 1e18) / 1_050_000_000_000_000_000;
        assertApproxEqRel(liqValue, expectedLiq, 1e13, "Liquidation should cap USDT premium");
    }
}

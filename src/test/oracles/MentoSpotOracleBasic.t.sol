// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { MentoSpotOracle } from "../../oracles/mento/MentoSpotOracle.sol";
import { ISortedOracles } from "../../oracles/mento/ISortedOracles.sol";
import { SortedOraclesMock } from "../../mocks/oracles/mento/SortedOraclesMock.sol";

/**
 * @title MentoSpotOracleBasicTest
 * @notice Basic tests for MentoSpotOracle focused on verifying the staleness bug fix
 * @dev Tests the critical fix: using medianTimestamp() instead of medianRate()'s second return value
 */
contract MentoSpotOracleBasicTest is Test {
    MentoSpotOracle public oracle;
    SortedOraclesMock public sortedOraclesMock;

    // Asset identifiers
    bytes6 public constant CKES_ID = 0x634B45530000; // "cKES"
    bytes6 public constant USDT_ID = 0x555344540000; // "USDT"

    // Mento feed ID (from Celo mainnet)
    address public constant KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

    // Test parameters
    uint256 public constant MAX_AGE = 3600; // 1 hour
    uint256 public constant MIN_PRICE = 66.67e18; // Min cKES per USD
    uint256 public constant MAX_PRICE = 200e18;   // Max cKES per USD

    function setUp() public {
        // Deploy mock
        sortedOraclesMock = new SortedOraclesMock();

        // Deploy oracle
        oracle = new MentoSpotOracle(ISortedOracles(address(sortedOraclesMock)));

        // Grant permissions
        oracle.grantRole(oracle.setSource.selector, address(this));
        oracle.grantRole(oracle.setBounds.selector, address(this));

        // Configure oracle source (maxAge is set here)
        oracle.setSource(CKES_ID, USDT_ID, KES_USD_FEED, MAX_AGE);

        // Set price bounds separately
        oracle.setBounds(CKES_ID, USDT_ID, MIN_PRICE, MAX_PRICE);

        // Set initial rate: 7.757e21 / 1e24 = 0.007757 USD per KES
        // Inverted: 1e42 / 7.757e21 = 128.92e18 cKES per USD
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21);
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
            bytes32(CKES_ID),
            bytes32(USDT_ID),
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
            bytes32(CKES_ID),
            bytes32(USDT_ID),
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
            bytes32(CKES_ID),
            bytes32(USDT_ID),
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
            bytes32(CKES_ID),
            bytes32(USDT_ID),
            100e18
        );
    }

    // ========== Price Inversion Tests ==========

    /**
     * @notice Test correct price inversion
     * @dev Verifies: cKES_per_USD = 1e42 / rateNumerator
     */
    function testPriceInversion() public {
        // Set rate: 7.757e21 (USD per KES in 1e24 precision)
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 7.757e21, block.timestamp);

        // Convert 100 USDT to cKES
        (uint256 value,) = oracle.peek(
            bytes32(CKES_ID),
            bytes32(USDT_ID),
            100e18
        );

        // Expected: 100 USDT * (1e42 / 7.757e21) / 1e18
        //         = 100 * 128.92e18 / 1e18
        //         = 12,892e18 cKES
        assertApproxEqRel(value, 12892e18, 0.01e18, "Inverted price should be ~12,892 cKES");
    }

    // ========== Bounds Tests ==========

    /**
     * @notice Test that prices below minimum are rejected
     */
    function testMinPriceBound() public {
        // Set a rate that would give cKES/USD below minimum (66.67e18)
        // If cKES/USD = 50e18, then USD/KES = 1e42 / 50e18 = 20e21
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 20e21, block.timestamp);

        vm.expectRevert("Price below minimum");
        oracle.peek(
            bytes32(CKES_ID),
            bytes32(USDT_ID),
            100e18
        );
    }

    /**
     * @notice Test that prices above maximum are rejected
     */
    function testMaxPriceBound() public {
        // Set a rate that would give cKES/USD above maximum (200e18)
        // If cKES/USD = 250e18, then USD/KES = 1e42 / 250e18 = 4e21
        sortedOraclesMock.setMedianRate(KES_USD_FEED, 4e21, block.timestamp);

        vm.expectRevert("Price above maximum");
        oracle.peek(
            bytes32(CKES_ID),
            bytes32(USDT_ID),
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
            bytes32(CKES_ID),
            bytes32(USDT_ID),
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
            bytes32(CKES_ID),
            bytes32(USDT_ID),
            1e18 // 1 USDT
        );
        assertApproxEqRel(value1, 128.92e18, 0.01e18, "1 USDT should give ~128.92 cKES");

        (uint256 value2,) = oracle.peek(
            bytes32(CKES_ID),
            bytes32(USDT_ID),
            1000e18 // 1000 USDT
        );
        assertApproxEqRel(value2, 128920e18, 0.01e18, "1000 USDT should give ~128,920 cKES");
    }
}

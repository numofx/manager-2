// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { MentoSpotOracle } from "src/oracles/mento/MentoSpotOracle.sol";
import { ISortedOracles } from "src/oracles/mento/ISortedOracles.sol";
import { SortedOraclesMock } from "src/mocks/oracles/mento/SortedOraclesMock.sol";
import { AggregatorV3Interface } from "src/oracles/chainlink/AggregatorV3Interface.sol";

contract ChainlinkAggregatorV3MockFull is AggregatorV3Interface {
    uint8 public override decimals;
    string public override description = "mock";
    uint256 public override version = 1;

    uint80 public roundId;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setRoundData(
        uint80 roundId_,
        int256 answer_,
        uint256 updatedAt_,
        uint80 answeredInRound_
    ) external {
        roundId = roundId_;
        answer = answer_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, answer, 0, updatedAt, answeredInRound);
    }

    function getRoundData(uint80)
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, answer, 0, updatedAt, answeredInRound);
    }
}

contract MentoSpotOracleIntegrationTest is Test {
    MentoSpotOracle public oracle;
    SortedOraclesMock public sortedOraclesMock;
    ChainlinkAggregatorV3MockFull public usdtUsdAggregator;

    bytes6 public constant CKES_ID = 0x634B45530000; // "cKES"
    bytes6 public constant USDT_ID = 0x555344540000; // "USDT"
    address public constant KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;
    uint256 public constant MAX_AGE = 3600;

    function setUp() public {
        vm.warp(1_000_000);

        sortedOraclesMock = new SortedOraclesMock();
        usdtUsdAggregator = new ChainlinkAggregatorV3MockFull(8);

        oracle = new MentoSpotOracle(
            ISortedOracles(address(sortedOraclesMock)),
            AggregatorV3Interface(address(usdtUsdAggregator))
        );

        oracle.grantRole(oracle.addSource.selector, address(this));
        oracle.addSource(USDT_ID, CKES_ID, KES_USD_FEED, MAX_AGE, 0);

        _setUsdtRound(1, 100_000_000, block.timestamp, 1); // 1.0 USDT/USD
        _setMentoRate(1e22, block.timestamp); // 0.01 USD/KES -> 100 cKES/USD
    }

    function _setUsdtRound(
        uint80 roundId,
        int256 answer,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal {
        usdtUsdAggregator.setRoundData(roundId, answer, updatedAt, answeredInRound);
    }

    function _setMentoRate(uint256 rateNumerator, uint256 timestamp) internal {
        sortedOraclesMock.setMedianRate(KES_USD_FEED, rateNumerator, timestamp);
    }

    function testBaseQuoteSameReturnsAmount() public {
        (uint256 value, uint256 updateTime) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(USDT_ID),
            123e18
        );

        assertEq(value, 123e18, "Should return amount for same asset");
        assertEq(updateTime, block.timestamp, "Should return current timestamp");
    }

    function testUpdateTimeUsesOlderUsdtTimestamp() public {
        uint256 mentoTime = block.timestamp - 100;
        uint256 usdtTime = block.timestamp - 200;

        _setMentoRate(1e22, mentoTime);
        _setUsdtRound(2, 100_000_000, usdtTime, 2);

        (, uint256 updateTime) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(CKES_ID),
            1e18
        );

        assertEq(updateTime, usdtTime, "Should use older timestamp");
    }

    function testUsdtUsdDecimalsScaling() public {
        ChainlinkAggregatorV3MockFull localAggregator = new ChainlinkAggregatorV3MockFull(6);
        MentoSpotOracle localOracle = new MentoSpotOracle(
            ISortedOracles(address(sortedOraclesMock)),
            AggregatorV3Interface(address(localAggregator))
        );

        localOracle.grantRole(localOracle.addSource.selector, address(this));
        localOracle.addSource(USDT_ID, CKES_ID, KES_USD_FEED, MAX_AGE, 0);

        localAggregator.setRoundData(1, 1_000_000, block.timestamp, 1); // 1.0 with 6 decimals
        _setMentoRate(1e22, block.timestamp); // 100 cKES/USD

        (uint256 value,) = localOracle.peek(
            bytes32(USDT_ID),
            bytes32(CKES_ID),
            10e18
        );

        assertEq(value, 1000e18, "Should scale USDT/USD to 1e18");
    }

    function testUsdtUsdInvalidNegativeAnswerReverts() public {
        _setMentoRate(1e22, block.timestamp);
        _setUsdtRound(2, -1, block.timestamp, 2);

        vm.expectRevert("USDT/USD invalid");
        oracle.peek(bytes32(USDT_ID), bytes32(CKES_ID), 1e18);
    }

    function testUsdtUsdInvalidZeroUpdatedAtReverts() public {
        _setMentoRate(1e22, block.timestamp);
        _setUsdtRound(2, 100_000_000, 0, 2);

        vm.expectRevert("USDT/USD invalid");
        oracle.peek(bytes32(USDT_ID), bytes32(CKES_ID), 1e18);
    }

    function testUsdtUsdInvalidAnsweredInRoundReverts() public {
        _setMentoRate(1e22, block.timestamp);
        _setUsdtRound(3, 100_000_000, block.timestamp, 2);

        vm.expectRevert("USDT/USD invalid");
        oracle.peek(bytes32(USDT_ID), bytes32(CKES_ID), 1e18);
    }

    function testUsdtUsdInvalidFutureTimestampReverts() public {
        _setMentoRate(1e22, block.timestamp);
        _setUsdtRound(2, 100_000_000, block.timestamp + 1, 2);

        vm.expectRevert("USDT/USD invalid");
        oracle.peek(bytes32(USDT_ID), bytes32(CKES_ID), 1e18);
    }

    function testUsdtUsdInvalidStaleTimestampReverts() public {
        _setMentoRate(1e22, block.timestamp);
        _setUsdtRound(2, 100_000_000, block.timestamp - (MAX_AGE + 1), 2);

        vm.expectRevert("USDT/USD invalid");
        oracle.peek(bytes32(USDT_ID), bytes32(CKES_ID), 1e18);
    }

    function testValueUsesUsdtPremium() public {
        _setMentoRate(1e22, block.timestamp); // 100 cKES/USD
        _setUsdtRound(2, 101_000_000, block.timestamp, 2); // 1.01

        (uint256 value,) = oracle.peek(
            bytes32(USDT_ID),
            bytes32(CKES_ID),
            10e18
        );

        assertEq(value, 1010e18, "Should apply USDT/USD premium");
    }

    function testUpdateRiskOffSetsOnInvalidFeed() public {
        _setUsdtRound(2, -1, block.timestamp, 2);

        oracle.updateRiskOff();

        assertTrue(oracle.riskOff(), "Risk-off should be true on invalid feed");
        assertEq(oracle.inBandCount(), 0, "inBandCount should reset");
    }

    function testUpdateRiskOffClearsAfterThreeInBandRounds() public {
        _setUsdtRound(2, -1, block.timestamp, 2);
        oracle.updateRiskOff();
        assertTrue(oracle.riskOff());

        _setUsdtRound(3, 100_000_000, block.timestamp, 3);
        oracle.updateRiskOff();
        assertEq(oracle.inBandCount(), 1);
        assertTrue(oracle.riskOff());

        _setUsdtRound(4, 100_000_000, block.timestamp, 4);
        oracle.updateRiskOff();
        assertEq(oracle.inBandCount(), 2);
        assertTrue(oracle.riskOff());

        _setUsdtRound(5, 100_000_000, block.timestamp, 5);
        oracle.updateRiskOff();
        assertEq(oracle.inBandCount(), 3);
        assertTrue(!oracle.riskOff(), "Risk-off should clear after 3 rounds");
    }

    function testUpdateRiskOffIgnoresSameRound() public {
        _setUsdtRound(2, 100_000_000, block.timestamp, 2);
        oracle.updateRiskOff();
        assertEq(oracle.inBandCount(), 1);

        _setUsdtRound(2, 100_000_000, block.timestamp, 2);
        oracle.updateRiskOff();
        assertEq(oracle.inBandCount(), 1, "Same round should not increment");
    }

    function testUpdateRiskOffResetsOnOutOfBand() public {
        _setUsdtRound(2, 100_000_000, block.timestamp, 2);
        oracle.updateRiskOff();
        assertEq(oracle.inBandCount(), 1);
        assertTrue(!oracle.riskOff());

        _setUsdtRound(3, 110_000_000, block.timestamp, 3);
        oracle.updateRiskOff();
        assertEq(oracle.inBandCount(), 0);
        assertTrue(oracle.riskOff(), "Out-of-band should set risk-off");
    }
}

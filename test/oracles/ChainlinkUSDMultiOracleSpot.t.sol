// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { ChainlinkUSDMultiOracleSpot } from "src/oracles/chainlink/ChainlinkUSDMultiOracleSpot.sol";
import { ChainlinkAggregatorV3MockEx } from "src/mocks/oracles/chainlink/ChainlinkAggregatorV3MockEx.sol";
import { ERC20Mock } from "src/mocks/ERC20Mock.sol";

contract ChainlinkUSDMultiOracleSpotTest is Test {
    bytes6 private constant BASE_ID = 0x424153450000; // "BASE"
    bytes6 private constant QUOTE_ID = 0x51554f544500; // "QUOTE"

    ChainlinkUSDMultiOracleSpot private oracle;
    ChainlinkAggregatorV3MockEx private baseUsd;
    ChainlinkAggregatorV3MockEx private quoteUsd;
    ERC20Mock private baseToken;
    ERC20Mock private quoteToken;

    function setUp() public {
        oracle = new ChainlinkUSDMultiOracleSpot();
        baseUsd = new ChainlinkAggregatorV3MockEx(8);
        quoteUsd = new ChainlinkAggregatorV3MockEx(8);
        baseToken = new ERC20Mock("Base Token", "BASE");
        quoteToken = new ERC20Mock("Quote Token", "QUOTE");

        oracle.grantRole(oracle.setSource.selector, address(this));

        baseUsd.set(1e8);
        vm.warp(block.timestamp + 10);
        quoteUsd.set(2e8);

        oracle.setSource(BASE_ID, baseToken, address(baseUsd));
        oracle.setSource(QUOTE_ID, quoteToken, address(quoteUsd));
    }

    function testLiquidationMatchesSpotAndGet() public {
        uint256 amountBase = 1e18;

        (uint256 spotPeek, uint256 peekTs) = oracle.peek(bytes32(BASE_ID), bytes32(QUOTE_ID), amountBase);
        (uint256 spotGet, uint256 getTs) = oracle.get(bytes32(BASE_ID), bytes32(QUOTE_ID), amountBase);
        (uint256 liqPeek, uint256 liqPeekTs) = oracle.peekLiquidation(bytes32(BASE_ID), bytes32(QUOTE_ID), amountBase);
        (uint256 liqGet, uint256 liqGetTs) = oracle.getLiquidation(bytes32(BASE_ID), bytes32(QUOTE_ID), amountBase);

        assertEq(spotPeek, 5e17, "spot price mismatch");
        assertEq(spotGet, spotPeek, "get != peek");
        assertEq(liqPeek, spotPeek, "liq peek != spot");
        assertEq(liqGet, spotPeek, "liq get != spot");

        assertEq(peekTs, baseUsd.timestamp(), "peek timestamp mismatch");
        assertEq(getTs, peekTs, "get timestamp mismatch");
        assertEq(liqPeekTs, peekTs, "liq peek timestamp mismatch");
        assertEq(liqGetTs, peekTs, "liq get timestamp mismatch");
    }

    function testIdentityPairForLiquidation() public {
        (uint256 amount, uint256 updateTime) =
            oracle.peekLiquidation(bytes32(BASE_ID), bytes32(BASE_ID), 123456789);
        assertEq(amount, 123456789);
        assertEq(updateTime, block.timestamp);
    }

    function testRiskOffAlwaysFalse() public {
        oracle.updateRiskOff();
        assertEq(oracle.riskOff(), false);
    }
}

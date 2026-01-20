// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { Cauldron } from "src/Cauldron.sol";
import { IFYToken } from "src/interfaces/IFYToken.sol";
import { RateOracleMock } from "src/mocks/oracles/RateOracleMock.sol";

contract FYTokenMock {
    address public underlying;
    uint256 public maturity;

    constructor(address underlying_, uint256 maturity_) {
        underlying = underlying_;
        maturity = maturity_;
    }
}

contract CauldronRateGuardTest is Test {
    Cauldron private cauldron;

    bytes6 private constant BASE_ID = 0x424153450000; // "BASE"
    bytes6 private constant SERIES_ID = bytes6("SER001");

    function setUp() public {
        cauldron = new Cauldron();
        cauldron.grantRole(Cauldron.addAsset.selector, address(this));
        cauldron.grantRole(Cauldron.setLendingOracle.selector, address(this));
        cauldron.grantRole(Cauldron.addSeries.selector, address(this));

        cauldron.addAsset(BASE_ID, address(0xBEEF));
    }

    function testAddSeriesRevertsWithoutOracle() public {
        FYTokenMock fyToken = new FYTokenMock(address(0xBEEF), block.timestamp);

        vm.expectRevert(bytes("Missing lending oracle"));
        cauldron.addSeries(SERIES_ID, BASE_ID, IFYToken(address(fyToken)));
    }

    function testSetLendingOracleRevertsMissingRateSource() public {
        RateOracleMock badOracle = new RateOracleMock();

        vm.expectRevert(bytes("Missing RATE source"));
        cauldron.setLendingOracle(BASE_ID, badOracle);
    }

    function testAddSeriesRevertsMissingRateSource() public {
        RateOracleMock oracle = new RateOracleMock();
        oracle.set(1);
        cauldron.setLendingOracle(BASE_ID, oracle);

        oracle.set(0);
        FYTokenMock fyToken = new FYTokenMock(address(0xBEEF), block.timestamp);

        vm.expectRevert(bytes("Missing RATE source"));
        cauldron.addSeries(SERIES_ID, BASE_ID, IFYToken(address(fyToken)));
    }

    function testOracleSwapFailsSafely() public {
        RateOracleMock goodOracle = new RateOracleMock();
        goodOracle.set(1);
        cauldron.setLendingOracle(BASE_ID, goodOracle);

        RateOracleMock badOracle = new RateOracleMock();
        vm.expectRevert(bytes("Missing RATE source"));
        cauldron.setLendingOracle(BASE_ID, badOracle);

        assertEq(address(cauldron.lendingOracles(BASE_ID)), address(goodOracle));
    }

    function testMatureWorksWithValidRateSource() public {
        RateOracleMock oracle = new RateOracleMock();
        oracle.set(1e18);
        cauldron.setLendingOracle(BASE_ID, oracle);

        FYTokenMock fyToken = new FYTokenMock(address(0xBEEF), block.timestamp);
        cauldron.addSeries(SERIES_ID, BASE_ID, IFYToken(address(fyToken)));

        cauldron.mature(SERIES_ID);
        assertEq(cauldron.ratesAtMaturity(SERIES_ID), 1e18);
    }
}

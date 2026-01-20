// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { Cauldron } from "src/Cauldron.sol";
import { IFYToken } from "src/interfaces/IFYToken.sol";
import { OracleMock } from "src/mocks/oracles/OracleMock.sol";
import { ERC20Mock } from "src/mocks/ERC20Mock.sol";
import { USDCMock } from "src/mocks/USDCMock.sol";

contract FYTokenMock {
    address public underlying;
    uint256 public maturity;

    constructor(address underlying_, uint256 maturity_) {
        underlying = underlying_;
        maturity = maturity_;
    }
}

contract CauldronIlkWadTest is Test {
    Cauldron private cauldron;
    OracleMock private spotOracle;
    OracleMock private rateOracle;

    bytes6 private constant BASE_ID = 0x424153450000; // "BASE"
    bytes6 private constant USDT_ID = 0x555344540000; // "USDT"
    bytes6 private constant ILK18_ID = 0x494c4b313800; // "ILK18"
    bytes6 private constant SERIES_ID = bytes6("SER001");

    bytes12 private constant USDT_VAULT_ID = bytes12("usdtvault1");
    bytes12 private constant ILK18_VAULT_ID = bytes12("ilk18valt");

    function setUp() public {
        cauldron = new Cauldron();
        spotOracle = new OracleMock();
        rateOracle = new OracleMock();

        cauldron.grantRole(Cauldron.addAsset.selector, address(this));
        cauldron.grantRole(Cauldron.setLendingOracle.selector, address(this));
        cauldron.grantRole(Cauldron.setSpotOracle.selector, address(this));
        cauldron.grantRole(Cauldron.setIlkToWad.selector, address(this));
        cauldron.grantRole(Cauldron.addSeries.selector, address(this));
        cauldron.grantRole(Cauldron.addIlks.selector, address(this));
        cauldron.grantRole(Cauldron.setDebtLimits.selector, address(this));
        cauldron.grantRole(Cauldron.build.selector, address(this));
        cauldron.grantRole(Cauldron.pour.selector, address(this));

        address base = address(new ERC20Mock("Base", "BASE"));
        address usdt = address(new USDCMock());
        address ilk18 = address(new ERC20Mock("Ilk18", "ILK18"));

        cauldron.addAsset(BASE_ID, base);
        cauldron.addAsset(USDT_ID, usdt);
        cauldron.addAsset(ILK18_ID, ilk18);

        cauldron.setLendingOracle(BASE_ID, rateOracle);
        cauldron.setSpotOracle(BASE_ID, USDT_ID, spotOracle, 1_000_000);
        cauldron.setSpotOracle(BASE_ID, ILK18_ID, spotOracle, 1_000_000);
        cauldron.setIlkToWad(USDT_ID, 1e12);
        cauldron.setIlkToWad(ILK18_ID, 1);
        spotOracle.set(1e18);
        rateOracle.set(1e18);

        FYTokenMock fyToken = new FYTokenMock(base, block.timestamp + 30 days);
        cauldron.addSeries(SERIES_ID, BASE_ID, IFYToken(address(fyToken)));

        bytes6[] memory ilks = new bytes6[](2);
        ilks[0] = USDT_ID;
        ilks[1] = ILK18_ID;
        cauldron.addIlks(SERIES_ID, ilks);

        cauldron.setDebtLimits(BASE_ID, USDT_ID, uint96(1e20), 0, 18);
        cauldron.setDebtLimits(BASE_ID, ILK18_ID, uint96(1e20), 0, 18);
    }

    function testUsdtCollateralWadScaleAllowsExpectedBorrow() public {
        cauldron.build(address(this), USDT_VAULT_ID, SERIES_ID, USDT_ID);
        cauldron.pour(USDT_VAULT_ID, int128(100e6), int128(100e18));
    }

    function testAddIlksRevertsWithoutScale() public {
        Cauldron localCauldron = new Cauldron();
        OracleMock localSpot = new OracleMock();
        OracleMock localRate = new OracleMock();

        localCauldron.grantRole(Cauldron.addAsset.selector, address(this));
        localCauldron.grantRole(Cauldron.setLendingOracle.selector, address(this));
        localCauldron.grantRole(Cauldron.setSpotOracle.selector, address(this));
        localCauldron.grantRole(Cauldron.addSeries.selector, address(this));
        localCauldron.grantRole(Cauldron.addIlks.selector, address(this));

        address base = address(new ERC20Mock("Base2", "BASE2"));
        address usdt = address(new USDCMock());
        localCauldron.addAsset(BASE_ID, base);
        localCauldron.addAsset(USDT_ID, usdt);

        localCauldron.setLendingOracle(BASE_ID, localRate);
        localCauldron.setSpotOracle(BASE_ID, USDT_ID, localSpot, 1_000_000);

        FYTokenMock fyToken = new FYTokenMock(base, block.timestamp + 30 days);
        localCauldron.addSeries(SERIES_ID, BASE_ID, IFYToken(address(fyToken)));

        bytes6[] memory ilks = new bytes6[](1);
        ilks[0] = USDT_ID;
        vm.expectRevert("Ilk scale not set");
        localCauldron.addIlks(SERIES_ID, ilks);
    }

    function test18DecCollateralMatchesPriorBehavior() public {
        cauldron.build(address(this), ILK18_VAULT_ID, SERIES_ID, ILK18_ID);
        cauldron.pour(ILK18_VAULT_ID, int128(100e18), int128(100e18));
    }
}

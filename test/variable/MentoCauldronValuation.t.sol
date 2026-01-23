// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { VRCauldron } from "src/variable/VRCauldron.sol";
import { AccumulatorMultiOracle } from "src/oracles/accumulator/AccumulatorMultiOracle.sol";
import { MentoSpotOracle } from "src/oracles/mento/MentoSpotOracle.sol";
import { ISortedOracles } from "src/oracles/mento/ISortedOracles.sol";
import { SortedOraclesMock } from "src/mocks/oracles/mento/SortedOraclesMock.sol";
import { ChainlinkAggregatorV3MockEx } from "src/mocks/oracles/chainlink/ChainlinkAggregatorV3MockEx.sol";
import { AggregatorV3Interface } from "src/oracles/chainlink/AggregatorV3Interface.sol";
import { ILiquidationOracle } from "src/interfaces/ILiquidationOracle.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { ERC20Mock } from "src/mocks/ERC20Mock.sol";
import { Math } from "@yield-protocol/utils-v2/src/utils/Math.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MentoCauldronValuationTest is Test, TestConstants {
    using Math for uint256;

    uint256 private constant INVERSION_SCALE = 1e42;

    VRCauldron public cauldron;
    AccumulatorMultiOracle public rateOracle;
    MentoSpotOracle public mentoOracle;
    SortedOraclesMock public sortedOraclesMock;
    ChainlinkAggregatorV3MockEx public usdtUsdAggregator;
    ERC20Mock public kesm;
    ERC20Mock public usdt;

    bytes6 public constant KESM_ID = 0x634B45530000; // "KESm"
    bytes6 public constant USDT_ID = 0x555344540000; // "USDT"
    address public constant KES_USD_FEED = address(0xBEEF);
    bytes12 public constant VAULT_ID = 0x000000000000000000000111;

    uint32 public constant COLLATERAL_RATIO = 1_500_000; // 150% in 6 decimals
    uint256 public constant MAX_AGE = 3600;

    function setUp() public {
        vm.warp(1_000_001);

        kesm = new ERC20Mock("KESm", "KESm");
        usdt = new ERC20Mock("USDT", "USDT");

        VRCauldron impl = new VRCauldron();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSignature("initialize(address)", address(this))
        );
        cauldron = VRCauldron(address(proxy));
        _grantCauldronRoles(address(this));

        sortedOraclesMock = new SortedOraclesMock();
        usdtUsdAggregator = new ChainlinkAggregatorV3MockEx(8);
        mentoOracle = new MentoSpotOracle(
            ISortedOracles(address(sortedOraclesMock)),
            AggregatorV3Interface(address(usdtUsdAggregator))
        );

        rateOracle = new AccumulatorMultiOracle();
        rateOracle.grantRole(AccumulatorMultiOracle.setSource.selector, address(this));
        rateOracle.setSource(KESM_ID, RATE, WAD, WAD);

        cauldron.addAsset(KESM_ID, address(kesm));
        cauldron.addAsset(USDT_ID, address(usdt));
        cauldron.setRateOracle(KESM_ID, IOracle(address(rateOracle)));
        cauldron.addBase(KESM_ID);

        mentoOracle.grantRole(MentoSpotOracle.addSource.selector, address(this));
        mentoOracle.addSource(USDT_ID, KESM_ID, KES_USD_FEED, MAX_AGE, 0);
        _setUsdtUsdPrice(100_000_000); // 1.0 with 8 decimals
        _setMentoRate(1e22); // USD/KES = 0.01 => 100 KESm/USD
        cauldron.setSpotOracle(KESM_ID, USDT_ID, IOracle(address(mentoOracle)), COLLATERAL_RATIO);

        bytes6[] memory ilks = new bytes6[](1);
        ilks[0] = USDT_ID;
        cauldron.addIlks(KESM_ID, ilks);
        cauldron.setDebtLimits(KESM_ID, USDT_ID, 1_000_000, 0, 18);

        cauldron.build(address(this), VAULT_ID, KESM_ID, USDT_ID);

    }

    function testCollateralValueMonotonicityOnWeakeningKES() public {
        cauldron.pour(VAULT_ID, int128(100e18), 0);

        int256 levelStrong = cauldron.level(VAULT_ID);
        _setMentoRate(2e22); // USD/KES = 0.02 => 50 KESm/USD
        int256 levelWeak = cauldron.level(VAULT_ID);

        assertGt(levelStrong, levelWeak);
        assertGt(levelWeak, 0);
    }

    function testMaxBorrowDecreasesWhenPriceDrops() public {
        uint128 ink = 100e18;
        cauldron.pour(VAULT_ID, int128(uint128(ink)), 0);

        uint256 maxStrong = _maxBorrowBase(ink);
        _setMentoRate(2e22);
        uint256 maxWeak = _maxBorrowBase(ink);

        assertGt(maxStrong, maxWeak);

        uint128 artStrong = cauldron.debtFromBase(KESM_ID, uint128(maxStrong));
        uint128 artWeak = cauldron.debtFromBase(KESM_ID, uint128(maxWeak));
        assertGt(artStrong, artWeak);
    }

    function testVaultSafeThenUnsafeOnPriceMove() public {
        cauldron.pour(VAULT_ID, int128(100e18), int128(6000e18));

        int256 levelSafe = cauldron.level(VAULT_ID);
        assertGt(levelSafe, 0);

        _setMentoRate(2e22);
        int256 levelUnsafe = cauldron.level(VAULT_ID);
        assertLt(levelUnsafe, 0);
    }

    function testLiquidationValueCapsUsdtPremium() public {
        cauldron.pour(VAULT_ID, int128(100e18), int128(5000e18));

        _setUsdtUsdPrice(105_000_000); // 1.05 USDT/USD

        (uint128 art, uint128 ink) = cauldron.balances(VAULT_ID);
        (IOracle oracle, uint32 ratio) = cauldron.spotOracles(KESM_ID, USDT_ID);

        (uint256 mintValue, ) = oracle.get(USDT_ID, KESM_ID, ink);
        (uint256 liqValue, ) = ILiquidationOracle(address(oracle)).getLiquidation(USDT_ID, KESM_ID, ink);
        assertGt(mintValue, liqValue);

        uint256 ratioNormalized = uint256(ratio) * 1e12;
        uint256 debtBase = cauldron.debtToBase(KESM_ID, art);
        int256 expectedLevel = int256(liqValue) - int256(debtBase.wmul(ratioNormalized));

        assertEq(cauldron.level(VAULT_ID), expectedLevel);
    }

    function testInversionAndVaultFlipAtCauldronBoundary() public {
        uint128 ink = 1000e18;
        uint256 rate150 = 150e8;
        uint256 rate200 = 200e8;
        _setMentoRate(_toMentoNumerator(rate150));
        _setUsdtUsdPrice(105_000_000); // 1.05 USDT/USD

        (uint256 value150, ) = mentoOracle.get(bytes32(USDT_ID), bytes32(KESM_ID), 1e18);

        uint256 maxBorrow = _maxBorrowBase(ink);
        uint256 borrow = maxBorrow - 1e18;
        cauldron.pour(VAULT_ID, int128(uint128(ink)), int128(int256(borrow)));

        assertGt(cauldron.level(VAULT_ID), 0);

        _setMentoRate(_toMentoNumerator(rate200));
        (uint256 value200, ) = mentoOracle.get(bytes32(USDT_ID), bytes32(KESM_ID), 1e18);

        uint256 expectedRatio = value150 * rate150 / rate200;
        assertApproxEqRel(value200, expectedRatio, 1e14, "KESm/USD should drop with USD/KES up");

        assertLt(cauldron.level(VAULT_ID), 0);

        uint256 invertedRate = INVERSION_SCALE / _toMentoNumerator(rate200);
        uint256 expectedLiq = uint256(ink).wmul(invertedRate);

        (IOracle oracle, ) = cauldron.spotOracles(KESM_ID, USDT_ID);
        (uint256 liqValue, ) = ILiquidationOracle(address(oracle)).getLiquidation(
            bytes32(USDT_ID),
            bytes32(KESM_ID),
            ink
        );
        assertEq(liqValue, expectedLiq, "Liquidation value should cap USDT premium");
    }

    function _maxBorrowBase(uint128 ink) internal returns (uint256 maxBase) {
        (IOracle oracle, uint32 ratio) = cauldron.spotOracles(KESM_ID, USDT_ID);
        (uint256 inkValue, ) = oracle.get(USDT_ID, KESM_ID, ink);
        uint256 ratioNormalized = uint256(ratio) * 1e12;
        maxBase = inkValue.wdiv(ratioNormalized);
    }

    function _setMentoRate(uint256 rateNumerator) internal {
        sortedOraclesMock.setMedianRate(KES_USD_FEED, rateNumerator, block.timestamp);
    }

    function _setUsdtUsdPrice(uint256 price) internal {
        usdtUsdAggregator.set(price);
    }

    function _toMentoNumerator(uint256 usdPerKes8) internal pure returns (uint256) {
        return usdPerKes8 * 1e16;
    }

    function _grantCauldronRoles(address user) internal {
        bytes4[] memory roles = new bytes4[](8);
        roles[0] = VRCauldron.addAsset.selector;
        roles[1] = VRCauldron.setRateOracle.selector;
        roles[2] = VRCauldron.addBase.selector;
        roles[3] = VRCauldron.setSpotOracle.selector;
        roles[4] = VRCauldron.addIlks.selector;
        roles[5] = VRCauldron.setDebtLimits.selector;
        roles[6] = VRCauldron.build.selector;
        roles[7] = VRCauldron.pour.selector;
        cauldron.grantRoles(roles, user);
    }
}

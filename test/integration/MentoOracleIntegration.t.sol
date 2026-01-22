// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { TestConstants } from "../utils/TestConstants.sol";
import { VRCauldron } from "src/variable/VRCauldron.sol";
import { AccumulatorMultiOracle } from "src/oracles/accumulator/AccumulatorMultiOracle.sol";
import { MentoSpotOracle } from "src/oracles/mento/MentoSpotOracle.sol";
import { ISortedOracles } from "src/oracles/mento/ISortedOracles.sol";
import { SortedOraclesMock } from "src/mocks/oracles/mento/SortedOraclesMock.sol";
import { AggregatorV3Interface } from "src/oracles/chainlink/AggregatorV3Interface.sol";
import { ILiquidationOracle } from "src/interfaces/ILiquidationOracle.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { ERC20Mock } from "src/mocks/ERC20Mock.sol";
import { Math } from "@yield-protocol/utils-v2/src/utils/Math.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

contract ChainlinkAggregatorV3MockRevertEmpty is AggregatorV3Interface {
    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external pure override returns (string memory) {
        return "revert";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert();
    }

    function latestRoundData()
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        revert();
    }
}

contract ChainlinkAggregatorV3MockDecimalsRevert is AggregatorV3Interface {
    function decimals() external pure override returns (uint8) {
        revert();
    }

    function description() external pure override returns (string memory) {
        return "decimals revert";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, 100_000_000, 0, 1_000_001, 1);
    }

    function latestRoundData()
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, 100_000_000, 0, 1_000_001, 1);
    }
}

contract ChainlinkAggregatorV3MockDecimalsHigh is AggregatorV3Interface {
    uint8 private immutable decimals_;

    constructor(uint8 decimalsHigh_) {
        decimals_ = decimalsHigh_;
    }

    function decimals() external view override returns (uint8) {
        return decimals_;
    }

    function description() external pure override returns (string memory) {
        return "decimals high";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, 100_000_000, 0, 1_000_001, 1);
    }

    function latestRoundData()
        external
        pure
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, 100_000_000, 0, 1_000_001, 1);
    }
}

contract MentoOracleIntegrationTest is Test, TestConstants {
    using Math for uint256;

    uint256 private constant INVERSION_SCALE = 1e42;

    VRCauldron public cauldron;
    AccumulatorMultiOracle public rateOracle;
    MentoSpotOracle public mentoOracle;
    SortedOraclesMock public sortedOraclesMock;
    ChainlinkAggregatorV3MockFull public usdtUsdAggregator;
    uint80 private usdtRoundId;

    ERC20Mock public ckes;
    ERC20Mock public usdt;

    bytes6 public constant CKES_ID = 0x634B45530000; // "cKES"
    bytes6 public constant USDT_ID = 0x555344540000; // "USDT"
    address public constant KES_USD_FEED = address(0xBEEF);
    bytes12 public constant VAULT_ID = 0x000000000000000000000111;

    uint32 public constant COLLATERAL_RATIO = 1_500_000;
    uint256 public constant MAX_AGE = 3600;

    function setUp() public {
        vm.warp(1_000_001);

        ckes = new ERC20Mock("cKES", "cKES");
        usdt = new ERC20Mock("USDT", "USDT");

        VRCauldron impl = new VRCauldron();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSignature("initialize(address)", address(this))
        );
        cauldron = VRCauldron(address(proxy));
        _grantCauldronRoles(address(this));

        sortedOraclesMock = new SortedOraclesMock();
        usdtUsdAggregator = new ChainlinkAggregatorV3MockFull(8);
        mentoOracle = new MentoSpotOracle(
            ISortedOracles(address(sortedOraclesMock)),
            AggregatorV3Interface(address(usdtUsdAggregator))
        );

        rateOracle = new AccumulatorMultiOracle();
        rateOracle.grantRole(AccumulatorMultiOracle.setSource.selector, address(this));
        rateOracle.setSource(CKES_ID, RATE, WAD, WAD);

        cauldron.addAsset(CKES_ID, address(ckes));
        cauldron.addAsset(USDT_ID, address(usdt));
        cauldron.setRateOracle(CKES_ID, IOracle(address(rateOracle)));
        cauldron.addBase(CKES_ID);

        mentoOracle.grantRole(MentoSpotOracle.addSource.selector, address(this));
        mentoOracle.grantRole(MentoSpotOracle.setBounds.selector, address(this));
        mentoOracle.addSource(USDT_ID, CKES_ID, KES_USD_FEED, MAX_AGE, 0);

        cauldron.setSpotOracle(CKES_ID, USDT_ID, IOracle(address(mentoOracle)), COLLATERAL_RATIO);
        bytes6[] memory ilks = new bytes6[](1);
        ilks[0] = USDT_ID;
        cauldron.addIlks(CKES_ID, ilks);
        cauldron.setDebtLimits(CKES_ID, USDT_ID, 1_000_000, 0, 18);

        cauldron.build(address(this), VAULT_ID, CKES_ID, USDT_ID);

        _setUsdtUsdSpot(100_000_000);
        _setMentoRateFromInvertedRate(100e18);
    }

    function testSpotBoundaryOneWeiFlip() public {
        bytes12 vaultId1 = bytes12(uint96(0x222));
        bytes12 vaultId2 = bytes12(uint96(0x333));
        bytes12 vaultId3 = bytes12(uint96(0x444));

        _buildVault(vaultId1);
        _buildVault(vaultId2);
        _buildVault(vaultId3);

        uint128 ink = 3e18;
        uint256 borrow = 200e18; // level == 0 when invertedRate == 100e18 and usdtUsd == 1e18

        // At boundary, level == 0; decreasing collateral value by 1 wei makes level < 0.
        cauldron.pour(vaultId1, int128(uint128(ink)), int128(int256(borrow)));

        _setMentoRateFromInvertedRate(100e18 - 1);
        vm.expectRevert("Undercollateralized");
        cauldron.pour(vaultId2, int128(uint128(ink)), int128(int256(borrow)));

        _setMentoRateFromInvertedRate(100e18);
        cauldron.pour(vaultId3, int128(uint128(ink)), int128(int256(borrow)));
    }

    function testLiquidationBoundaryOneWeiFlip() public {
        uint128 ink = 3e18;
        uint256 borrow = 200e18;

        // At boundary, level == 0; decreasing collateral value by 1 wei makes level < 0.
        cauldron.pour(VAULT_ID, int128(uint128(ink)), int128(int256(borrow)));

        int256 levelAtPrice = cauldron.level(VAULT_ID);
        assertEq(levelAtPrice, 0);

        _setMentoRateFromInvertedRate(100e18 - 1);
        int256 levelWorse = cauldron.level(VAULT_ID);
        assertLt(levelWorse, 0);

        _setMentoRateFromInvertedRate(100e18);
        int256 levelBack = cauldron.level(VAULT_ID);
        assertEq(levelBack, 0);
    }

    function testWrongInversionBoundsRevert() public {
        mentoOracle.setBounds(USDT_ID, CKES_ID, 0.005e18, 0.015e18);
        vm.expectRevert("Price above maximum");
        mentoOracle.get(bytes32(USDT_ID), bytes32(CKES_ID), 1e18);
    }

    function testDecimalsMatrix() public {
        _setMentoRateFromInvertedRate(100e18);

        uint8[4] memory tokenDecimals = [uint8(6), 18, 6, 18];
        uint8[4] memory feedDecimals = [uint8(8), 8, 18, 18];

        for (uint256 i = 0; i < tokenDecimals.length; i++) {
            uint8 tokenDec = tokenDecimals[i];
            uint8 feedDec = feedDecimals[i];

            ChainlinkAggregatorV3MockFull feed = new ChainlinkAggregatorV3MockFull(feedDec);
            MentoSpotOracle oracle = new MentoSpotOracle(
                ISortedOracles(address(sortedOraclesMock)),
                AggregatorV3Interface(address(feed))
            );
            oracle.grantRole(MentoSpotOracle.addSource.selector, address(this));
            oracle.addSource(USDT_ID, CKES_ID, KES_USD_FEED, MAX_AGE, 0);

            uint256 answer = feedDec == 8 ? 100_000_000 : 1e18;
            feed.setRoundData(1, int256(answer), block.timestamp, 1);

            uint256 amount = 10 ** tokenDec;
            uint256 usdtUsd = feedDec == 8 ? answer * 1e10 : answer;
            uint256 expected = amount.wmul(100e18).wmul(usdtUsd);

            (uint256 value, ) = oracle.get(bytes32(USDT_ID), bytes32(CKES_ID), amount);
            assertEq(value, expected);
        }
    }

    function testBadFeedRevertsCauldronBorrow() public {
        cauldron.pour(VAULT_ID, int128(uint128(10e18)), 0);

        _setUsdtRound(2, -1, block.timestamp, 2);
        _expectRiskOffRevert();
        cauldron.pour(VAULT_ID, 0, int128(int256(1e18)));

        _setUsdtRound(3, 100_000_000, 0, 3);
        _expectRiskOffRevert();
        cauldron.pour(VAULT_ID, 0, int128(int256(1e18)));

        _setUsdtRound(4, 100_000_000, block.timestamp + 1, 4);
        _expectRiskOffRevert();
        cauldron.pour(VAULT_ID, 0, int128(int256(1e18)));

        _setUsdtRound(5, 100_000_000, block.timestamp - (MAX_AGE + 1), 5);
        _expectRiskOffRevert();
        cauldron.pour(VAULT_ID, 0, int128(int256(1e18)));

        _setUsdtRound(6, 100_000_000, block.timestamp, 5);
        _expectRiskOffRevert();
        cauldron.pour(VAULT_ID, 0, int128(int256(1e18)));
    }

    function testDecimalsRevertCausesRiskOff() public {
        ChainlinkAggregatorV3MockDecimalsRevert feed = new ChainlinkAggregatorV3MockDecimalsRevert();
        MentoSpotOracle oracle = new MentoSpotOracle(
            ISortedOracles(address(sortedOraclesMock)),
            AggregatorV3Interface(address(feed))
        );
        oracle.grantRole(MentoSpotOracle.addSource.selector, address(this));
        oracle.addSource(USDT_ID, CKES_ID, KES_USD_FEED, MAX_AGE, 0);

        cauldron.setSpotOracle(CKES_ID, USDT_ID, IOracle(address(oracle)), COLLATERAL_RATIO);

        cauldron.pour(VAULT_ID, int128(uint128(10e18)), 0);
        _expectRiskOffRevert();
        cauldron.pour(VAULT_ID, 0, int128(int256(1e18)));
    }

    function testDecimalsHighCausesRiskOff() public {
        ChainlinkAggregatorV3MockDecimalsHigh feed = new ChainlinkAggregatorV3MockDecimalsHigh(19);
        MentoSpotOracle oracle = new MentoSpotOracle(
            ISortedOracles(address(sortedOraclesMock)),
            AggregatorV3Interface(address(feed))
        );
        oracle.grantRole(MentoSpotOracle.addSource.selector, address(this));
        oracle.addSource(USDT_ID, CKES_ID, KES_USD_FEED, MAX_AGE, 0);

        cauldron.setSpotOracle(CKES_ID, USDT_ID, IOracle(address(oracle)), COLLATERAL_RATIO);

        cauldron.pour(VAULT_ID, int128(uint128(10e18)), 0);
        _expectRiskOffRevert();
        cauldron.pour(VAULT_ID, 0, int128(int256(1e18)));
    }

    function testPremiumCapBoundaries() public {
        uint256 amount = 10e18;

        _setUsdtUsdSpot(99_999_999);
        (uint256 mintUnder, ) = mentoOracle.get(bytes32(USDT_ID), bytes32(CKES_ID), amount);
        (uint256 liqUnder, ) = mentoOracle.getLiquidation(bytes32(USDT_ID), bytes32(CKES_ID), amount);
        assertEq(mintUnder, liqUnder);

        _setUsdtUsdSpot(100_000_000);
        (uint256 mintAt, ) = mentoOracle.get(bytes32(USDT_ID), bytes32(CKES_ID), amount);
        (uint256 liqAt, ) = mentoOracle.getLiquidation(bytes32(USDT_ID), bytes32(CKES_ID), amount);
        assertEq(mintAt, liqAt);

        _setUsdtUsdSpot(100_000_001);
        (uint256 mintOver, ) = mentoOracle.get(bytes32(USDT_ID), bytes32(CKES_ID), amount);
        (uint256 liqOver, ) = mentoOracle.getLiquidation(bytes32(USDT_ID), bytes32(CKES_ID), amount);
        assertGt(mintOver, liqOver);

        uint256 expectedLiq = amount.wmul(100e18);
        assertEq(liqOver, expectedLiq);
    }

    function testEmptyRevertBubblesToRiskOff() public {
        ChainlinkAggregatorV3MockRevertEmpty feed = new ChainlinkAggregatorV3MockRevertEmpty();
        MentoSpotOracle oracle = new MentoSpotOracle(
            ISortedOracles(address(sortedOraclesMock)),
            AggregatorV3Interface(address(feed))
        );
        oracle.grantRole(MentoSpotOracle.addSource.selector, address(this));
        oracle.addSource(USDT_ID, CKES_ID, KES_USD_FEED, MAX_AGE, 0);

        cauldron.setSpotOracle(CKES_ID, USDT_ID, IOracle(address(oracle)), COLLATERAL_RATIO);

        cauldron.pour(VAULT_ID, int128(uint128(10e18)), 0);
        _expectRiskOffRevert();
        cauldron.pour(VAULT_ID, 0, int128(int256(1e18)));
    }

    function _setUsdtUsdSpot(uint256 price1e8) internal {
        usdtRoundId++;
        usdtUsdAggregator.setRoundData(usdtRoundId, int256(price1e8), block.timestamp, usdtRoundId);
    }

    function _setUsdtRound(
        uint80 roundId,
        int256 answer,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal {
        usdtUsdAggregator.setRoundData(roundId, answer, updatedAt, answeredInRound);
    }

    function _setKesUsdMento(uint256 rateNumerator, uint256 rateDenominator) internal {
        sortedOraclesMock.setMedianRateWithDenominator(
            KES_USD_FEED,
            rateNumerator,
            rateDenominator,
            block.timestamp
        );
    }

    function _setMentoRateFromInvertedRate(uint256 invertedRate) internal {
        _setKesUsdMento(INVERSION_SCALE / invertedRate, 1e24);
    }

    function _buildVault(bytes12 vaultId) internal {
        cauldron.build(address(this), vaultId, CKES_ID, USDT_ID);
    }

    function _expectRiskOffRevert() internal {
        vm.expectRevert("RISK_OFF");
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

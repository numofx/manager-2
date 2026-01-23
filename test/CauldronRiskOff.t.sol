// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { Cauldron } from "src/Cauldron.sol";
import { IFYToken } from "src/interfaces/IFYToken.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { OracleMock } from "src/mocks/oracles/OracleMock.sol";
import { RateOracleMock } from "src/mocks/oracles/RateOracleMock.sol";

contract FYTokenRiskMock {
    address public underlying;
    uint256 public maturity;

    constructor(address underlying_, uint256 maturity_) {
        underlying = underlying_;
        maturity = maturity_;
    }
}

contract CauldronRiskOffTest is Test {
    Cauldron private cauldron;
    OracleMock private spotOracle;
    RateOracleMock private rateOracle;

    bytes6 private constant BASE_ID = 0x424153450000; // "BASE"
    bytes6 private constant ILK_ID = 0x494c4b310000; // "ILK1"
    bytes6 private constant SERIES_ID = bytes6("SER001");
    bytes12 private constant VAULT_ID = bytes12("riskvault");

    function setUp() public {
        cauldron = new Cauldron();
        spotOracle = new OracleMock();
        rateOracle = new RateOracleMock();

        cauldron.grantRole(Cauldron.addAsset.selector, address(this));
        cauldron.grantRole(Cauldron.setLendingOracle.selector, address(this));
        cauldron.grantRole(Cauldron.setSpotOracle.selector, address(this));
        cauldron.grantRole(Cauldron.setIlkToWad.selector, address(this));
        cauldron.grantRole(Cauldron.addSeries.selector, address(this));
        cauldron.grantRole(Cauldron.addIlks.selector, address(this));
        cauldron.grantRole(Cauldron.setDebtLimits.selector, address(this));
        cauldron.grantRole(Cauldron.build.selector, address(this));
        cauldron.grantRole(Cauldron.pour.selector, address(this));

        cauldron.addAsset(BASE_ID, address(0xBEEF));
        cauldron.addAsset(ILK_ID, address(0xCAFE));
        cauldron.setIlkToWad(ILK_ID, 1);

        rateOracle.set(1e18);
        cauldron.setLendingOracle(BASE_ID, rateOracle);
        cauldron.setSpotOracle(BASE_ID, ILK_ID, spotOracle, 1_000_000);

        FYTokenRiskMock fyToken = new FYTokenRiskMock(address(0xBEEF), block.timestamp + 30 days);
        cauldron.addSeries(SERIES_ID, BASE_ID, IFYToken(address(fyToken)));

        bytes6[] memory ilks = new bytes6[](1);
        ilks[0] = ILK_ID;
        cauldron.addIlks(SERIES_ID, ilks);
        cauldron.setDebtLimits(BASE_ID, ILK_ID, uint96(1e20), 0, 18);

        cauldron.build(address(this), VAULT_ID, SERIES_ID, ILK_ID);
    }

    function testRiskOffSpotOracleUnsetReverts() public {
        vm.record();
        (IOracle oracle, uint32 ratio) = cauldron.spotOracles(BASE_ID, ILK_ID);
        (bytes32[] memory reads,) = vm.accesses(address(cauldron));
        bytes32 slot = _findSpotOracleSlot(address(cauldron), reads, address(oracle), ratio);
        vm.store(address(cauldron), slot, bytes32(0));

        vm.expectRevert("Spot oracle not found");
        cauldron.pour(VAULT_ID, 0, int128(1e18));
    }

    function testUpdateRiskOffRevertBubbles() public {
        spotOracle.setRevertUpdateRiskOff(true);
        vm.expectRevert("UPDATE_RISK_OFF_REVERT");
        cauldron.pour(VAULT_ID, 0, int128(1e18));
    }

    function testRiskOffRevertBubbles() public {
        spotOracle.setRevertRiskOff(true);
        vm.expectRevert("RISK_OFF_REVERT");
        cauldron.pour(VAULT_ID, 0, int128(1e18));
    }

    function testRiskOffTrueReverts() public {
        spotOracle.setRiskOff(true);
        vm.expectRevert("RISK_OFF");
        cauldron.pour(VAULT_ID, 0, int128(1e18));
    }

    function testRiskOffLiquidationRevertBubbles() public {
        spotOracle.setRevertLiquidation(true);
        vm.expectRevert("LIQUIDATION_REVERT");
        cauldron.level(VAULT_ID);
    }

    function _findSpotOracleSlot(
        address target,
        bytes32[] memory reads,
        address oracle,
        uint32 ratio
    ) internal view returns (bytes32) {
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        for (uint256 i; i < reads.length; i++) {
            if (reads[i] == implSlot) continue;
            bytes32 value = vm.load(target, reads[i]);
            address storedOracle = address(uint160(uint256(value)));
            uint32 storedRatio = uint32(uint256(value >> 160));
            if (storedOracle == oracle && storedRatio == ratio) {
                return reads[i];
            }
        }
        revert("Spot oracle slot not found");
    }
}

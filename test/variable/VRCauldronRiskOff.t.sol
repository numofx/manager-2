// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { VRCauldron } from "src/variable/VRCauldron.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { OracleMock } from "src/mocks/oracles/OracleMock.sol";
import { RateOracleMock } from "src/mocks/oracles/RateOracleMock.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VRCauldronRiskOffTest is Test {
    VRCauldron private cauldron;
    OracleMock private spotOracle;
    RateOracleMock private rateOracle;

    bytes6 private constant BASE_ID = 0x424153450000; // "BASE"
    bytes6 private constant ILK_ID = 0x494c4b310000; // "ILK1"
    bytes12 private constant VAULT_ID = bytes12("vriskvault");

    function setUp() public {
        VRCauldron implementation = new VRCauldron();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSignature("initialize(address)", address(this))
        );
        cauldron = VRCauldron(address(proxy));

        spotOracle = new OracleMock();
        rateOracle = new RateOracleMock();
        rateOracle.set(1e18);

        cauldron.grantRole(cauldron.addAsset.selector, address(this));
        cauldron.grantRole(cauldron.setRateOracle.selector, address(this));
        cauldron.grantRole(cauldron.addBase.selector, address(this));
        cauldron.grantRole(cauldron.setSpotOracle.selector, address(this));
        cauldron.grantRole(cauldron.addIlks.selector, address(this));
        cauldron.grantRole(cauldron.build.selector, address(this));
        cauldron.grantRole(cauldron.pour.selector, address(this));

        cauldron.addAsset(BASE_ID, address(0xBEEF));
        cauldron.addAsset(ILK_ID, address(0xCAFE));
        cauldron.setRateOracle(BASE_ID, rateOracle);
        cauldron.addBase(BASE_ID);
        cauldron.setSpotOracle(BASE_ID, ILK_ID, spotOracle, 1_000_000);

        bytes6[] memory ilks = new bytes6[](1);
        ilks[0] = ILK_ID;
        cauldron.addIlks(BASE_ID, ilks);

        cauldron.build(address(this), VAULT_ID, BASE_ID, ILK_ID);
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

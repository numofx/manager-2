// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { Cauldron } from "src/Cauldron.sol";
import { IFYToken } from "src/interfaces/IFYToken.sol";
import { OracleMock } from "src/mocks/oracles/OracleMock.sol";

contract FYTokenMock {
    address public underlying;
    uint256 public maturity;

    constructor(address underlying_, uint256 maturity_) {
        underlying = underlying_;
        maturity = maturity_;
    }
}

contract CauldronRollTest is Test {
    Cauldron private cauldron;
    OracleMock private spotOracle;
    OracleMock private rateOracle;

    bytes6 private constant BASE_ID = 0x424153450000; // "BASE"
    bytes6 private constant ILK_ID = 0x494c4b310000; // "ILK1"
    bytes6 private constant SERIES1_ID = bytes6("SER001");
    bytes6 private constant SERIES2_ID = bytes6("SER002");
    bytes12 private constant VAULT_ID = bytes12("vaultroll");

    bytes32 private constant VAULT_POURED_TOPIC =
        keccak256("VaultPoured(bytes12,bytes6,bytes6,int128,int128)");

    function setUp() public {
        cauldron = new Cauldron();
        spotOracle = new OracleMock();
        rateOracle = new OracleMock();

        cauldron.grantRole(Cauldron.addAsset.selector, address(this));
        cauldron.grantRole(Cauldron.setLendingOracle.selector, address(this));
        cauldron.grantRole(Cauldron.setSpotOracle.selector, address(this));
        cauldron.grantRole(Cauldron.addSeries.selector, address(this));
        cauldron.grantRole(Cauldron.addIlks.selector, address(this));
        cauldron.grantRole(Cauldron.setDebtLimits.selector, address(this));
        cauldron.grantRole(Cauldron.build.selector, address(this));
        cauldron.grantRole(Cauldron.pour.selector, address(this));
        cauldron.grantRole(Cauldron.roll.selector, address(this));

        address base = address(0xBEEF);
        address ilk = address(0xCAFE);
        cauldron.addAsset(BASE_ID, base);
        cauldron.addAsset(ILK_ID, ilk);

        cauldron.setLendingOracle(BASE_ID, rateOracle);
        cauldron.setSpotOracle(BASE_ID, ILK_ID, spotOracle, 1_000_000);
        spotOracle.set(1e18);
        rateOracle.set(1e18);

        uint256 maturity1 = block.timestamp + 30 days;
        uint256 maturity2 = block.timestamp + 60 days;
        FYTokenMock fyToken1 = new FYTokenMock(base, maturity1);
        FYTokenMock fyToken2 = new FYTokenMock(base, maturity2);

        cauldron.addSeries(SERIES1_ID, BASE_ID, IFYToken(address(fyToken1)));
        cauldron.addSeries(SERIES2_ID, BASE_ID, IFYToken(address(fyToken2)));

        bytes6[] memory ilks = new bytes6[](1);
        ilks[0] = ILK_ID;
        cauldron.addIlks(SERIES1_ID, ilks);
        cauldron.addIlks(SERIES2_ID, ilks);

        cauldron.setDebtLimits(BASE_ID, ILK_ID, uint96(1e20), 0, 18);
    }

    function testRollEmitsVaultPouredWithNewSeries() public {
        cauldron.build(address(this), VAULT_ID, SERIES1_ID, ILK_ID);
        cauldron.pour(VAULT_ID, int128(2e18), int128(1e18));

        vm.recordLogs();
        cauldron.roll(VAULT_ID, SERIES2_ID, 0);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < entries.length; i++) {
            Vm.Log memory entry = entries[i];
            if (entry.topics.length == 4 && entry.topics[0] == VAULT_POURED_TOPIC) {
                bool vaultOk = entry.topics[1] == bytes32(VAULT_ID);
                bool seriesOk = entry.topics[2] == bytes32(SERIES2_ID);
                bool ilkOk = entry.topics[3] == bytes32(ILK_ID);
                if (vaultOk && seriesOk && ilkOk) {
                    found = true;
                    break;
                }
            }
        }

        assertTrue(found, "missing VaultPoured for new series");
        (, bytes6 seriesId, ) = cauldron.vaults(VAULT_ID);
        assertEq(seriesId, SERIES2_ID);
    }
}

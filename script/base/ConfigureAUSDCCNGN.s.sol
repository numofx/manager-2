// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import "../../src/Cauldron.sol";
import "../../src/Ladle.sol";
import "../../src/Witch.sol";
import "../../src/Join.sol";
import "../../src/interfaces/IJoin.sol";
import "../../src/interfaces/IOracle.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";

/**
 * @title ConfigureAUSDCCNGN
 * @notice Configure Base market wiring for cNGN base with aUSDC collateral
 *
 * Required environment variables:
 * - PRIVATE_KEY
 * - CAULDRON_ADDRESS
 * - LADLE_ADDRESS
 * - WITCH_ADDRESS
 * - AUSDC_ADDRESS
 * - CNGN_ADDRESS
 * - AUSDC_JOIN_ADDRESS
 * - CNGN_JOIN_ADDRESS
 * - LENDING_ORACLE_ADDRESS
 * - SPOT_ORACLE_ADDRESS
 * - MAX_DEBT
 * - MIN_DEBT
 * - DEBT_DECIMALS
 * - COLLATERAL_RATIO
 */
contract ConfigureAUSDCCNGN is Script {
    bytes6 constant AUSDC_ID = 0x615553444300; // "aUSDC\0"
    bytes6 constant CNGN_ID = 0x634e474e0000; // "cNGN\0\0"

    struct Config {
        uint256 adminPrivateKey;
        address admin;
        Cauldron cauldron;
        Ladle ladle;
        Witch witch;
        address ausdc;
        address cngn;
        Join ausdcJoin;
        Join cngnJoin;
        IOracle lendingOracle;
        IOracle spotOracle;
        uint96 maxDebt;
        uint24 minDebt;
        uint8 debtDecimals;
        uint32 collateralRatio;
        uint256 ausdcIlkToWad;
        uint256 cngnIlkToWad;
    }

    function _load() private returns (Config memory c) {
        c.adminPrivateKey = vm.envUint("PRIVATE_KEY");
        c.admin = vm.addr(c.adminPrivateKey);
        c.cauldron = Cauldron(vm.envAddress("CAULDRON_ADDRESS"));
        c.ladle = Ladle(payable(vm.envAddress("LADLE_ADDRESS")));
        c.witch = Witch(vm.envAddress("WITCH_ADDRESS"));
        c.ausdc = vm.envAddress("AUSDC_ADDRESS");
        c.cngn = vm.envAddress("CNGN_ADDRESS");
        c.ausdcJoin = Join(vm.envAddress("AUSDC_JOIN_ADDRESS"));
        c.cngnJoin = Join(vm.envAddress("CNGN_JOIN_ADDRESS"));
        c.lendingOracle = IOracle(vm.envAddress("LENDING_ORACLE_ADDRESS"));
        c.spotOracle = IOracle(vm.envAddress("SPOT_ORACLE_ADDRESS"));
        c.maxDebt = uint96(vm.envUint("MAX_DEBT"));
        c.minDebt = uint24(vm.envUint("MIN_DEBT"));
        c.debtDecimals = uint8(vm.envUint("DEBT_DECIMALS"));
        c.collateralRatio = uint32(vm.envUint("COLLATERAL_RATIO"));
        c.ausdcIlkToWad = vm.envOr("AUSDC_ILK_TO_WAD", uint256(0));
        c.cngnIlkToWad = vm.envOr("CNGN_ILK_TO_WAD", uint256(0));
    }

    function run() external {
        Config memory c = _load();

        vm.startBroadcast(c.adminPrivateKey);

        // Grant admin permissions to the broadcaster EOA.
        c.cauldron.grantRole(Cauldron.addAsset.selector, c.admin);
        c.cauldron.grantRole(Cauldron.setIlkToWad.selector, c.admin);
        c.cauldron.grantRole(Cauldron.setLendingOracle.selector, c.admin);
        c.cauldron.grantRole(Cauldron.setSpotOracle.selector, c.admin);
        c.cauldron.grantRole(Cauldron.setDebtLimits.selector, c.admin);
        c.cauldron.grantRole(Cauldron.addSeries.selector, c.admin);
        c.cauldron.grantRole(Cauldron.addIlks.selector, c.admin);
        c.ladle.grantRole(Ladle.addJoin.selector, c.admin);

        // Core protocol permissions.
        c.cauldron.grantRole(Cauldron.build.selector, address(c.ladle));
        c.cauldron.grantRole(Cauldron.destroy.selector, address(c.ladle));
        c.cauldron.grantRole(Cauldron.tweak.selector, address(c.ladle));
        c.cauldron.grantRole(Cauldron.give.selector, address(c.ladle));
        c.cauldron.grantRole(Cauldron.pour.selector, address(c.ladle));
        c.cauldron.grantRole(Cauldron.stir.selector, address(c.ladle));
        c.cauldron.grantRole(Cauldron.roll.selector, address(c.ladle));
        c.cauldron.grantRole(Cauldron.give.selector, address(c.witch));
        c.cauldron.grantRole(Cauldron.pour.selector, address(c.witch));
        c.cauldron.grantRole(Cauldron.slurp.selector, address(c.witch));

        // Validate join-asset wiring.
        require(c.ausdcJoin.asset() == c.ausdc, "aUSDC join mismatch");
        require(c.cngnJoin.asset() == c.cngn, "cNGN join mismatch");

        // Join permissions.
        c.ausdcJoin.grantRole(IJoin.join.selector, address(c.ladle));
        c.ausdcJoin.grantRole(IJoin.exit.selector, address(c.ladle));
        c.ausdcJoin.grantRole(IJoin.exit.selector, address(c.witch));
        c.cngnJoin.grantRole(IJoin.join.selector, address(c.ladle));
        c.cngnJoin.grantRole(IJoin.exit.selector, address(c.ladle));
        c.cngnJoin.grantRole(IJoin.exit.selector, address(c.witch));

        // Assets.
        if (c.cauldron.assets(AUSDC_ID) == address(0)) c.cauldron.addAsset(AUSDC_ID, c.ausdc);
        if (c.cauldron.assets(CNGN_ID) == address(0)) c.cauldron.addAsset(CNGN_ID, c.cngn);

        // Normalize collateral/base amounts to 18-dec wad.
        // Optional env overrides avoid metadata calls in environments where staticcalls fail.
        if (c.ausdcIlkToWad == 0) {
            uint8 ausdcDecimals = IERC20Metadata(c.ausdc).decimals();
            require(ausdcDecimals <= 18, "Unsupported AUSDC decimals");
            c.ausdcIlkToWad = 10 ** (18 - ausdcDecimals);
        }
        if (c.cngnIlkToWad == 0) {
            uint8 cngnDecimals = IERC20Metadata(c.cngn).decimals();
            require(cngnDecimals <= 18, "Unsupported CNGN decimals");
            c.cngnIlkToWad = 10 ** (18 - cngnDecimals);
        }
        c.cauldron.setIlkToWad(AUSDC_ID, c.ausdcIlkToWad);
        c.cauldron.setIlkToWad(CNGN_ID, c.cngnIlkToWad);

        // Ladle join registry.
        if (address(c.ladle.joins(AUSDC_ID)) != address(c.ausdcJoin)) c.ladle.addJoin(AUSDC_ID, IJoin(address(c.ausdcJoin)));
        if (address(c.ladle.joins(CNGN_ID)) != address(c.cngnJoin)) c.ladle.addJoin(CNGN_ID, IJoin(address(c.cngnJoin)));

        // Oracle + risk parameters.
        c.cauldron.setLendingOracle(CNGN_ID, c.lendingOracle);
        c.cauldron.setSpotOracle(CNGN_ID, AUSDC_ID, c.spotOracle, c.collateralRatio);
        c.cauldron.setDebtLimits(CNGN_ID, AUSDC_ID, c.maxDebt, c.minDebt, c.debtDecimals);

        vm.stopBroadcast();
    }
}

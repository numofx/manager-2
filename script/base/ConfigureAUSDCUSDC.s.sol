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
 * @title ConfigureAUSDCUSDC
 * @notice Configure Base market wiring for USDC base with aUSDC collateral
 *
 * Required environment variables:
 * - PRIVATE_KEY
 * - CAULDRON_ADDRESS
 * - LADLE_ADDRESS
 * - WITCH_ADDRESS
 * - AUSDC_ADDRESS
 * - USDC_ADDRESS
 * - AUSDC_JOIN_ADDRESS
 * - USDC_JOIN_ADDRESS
 * - LENDING_ORACLE_ADDRESS
 * - SPOT_ORACLE_ADDRESS
 * - MAX_DEBT
 * - MIN_DEBT
 * - DEBT_DECIMALS
 * - COLLATERAL_RATIO
 */
contract ConfigureAUSDCUSDC is Script {
    bytes6 constant AUSDC_ID = 0x615553444300; // "aUSDC\0"
    bytes6 constant USDC_ID = 0x555344430000; // "USDC\0\0"

    struct Config {
        uint256 adminPrivateKey;
        address admin;
        Cauldron cauldron;
        Ladle ladle;
        Witch witch;
        address ausdc;
        address usdc;
        Join ausdcJoin;
        Join usdcJoin;
        IOracle lendingOracle;
        IOracle spotOracle;
        uint96 maxDebt;
        uint24 minDebt;
        uint8 debtDecimals;
        uint32 collateralRatio;
        uint256 ausdcIlkToWad;
        uint256 usdcIlkToWad;
    }

    function _load() private returns (Config memory c) {
        c.adminPrivateKey = vm.envUint("PRIVATE_KEY");
        c.admin = vm.addr(c.adminPrivateKey);
        c.cauldron = Cauldron(vm.envAddress("CAULDRON_ADDRESS"));
        c.ladle = Ladle(payable(vm.envAddress("LADLE_ADDRESS")));
        c.witch = Witch(vm.envAddress("WITCH_ADDRESS"));
        c.ausdc = vm.envAddress("AUSDC_ADDRESS");
        c.usdc = vm.envAddress("USDC_ADDRESS");
        c.ausdcJoin = Join(vm.envAddress("AUSDC_JOIN_ADDRESS"));
        c.usdcJoin = Join(vm.envAddress("USDC_JOIN_ADDRESS"));
        c.lendingOracle = IOracle(vm.envAddress("LENDING_ORACLE_ADDRESS"));
        c.spotOracle = IOracle(vm.envAddress("SPOT_ORACLE_ADDRESS"));
        c.maxDebt = uint96(vm.envUint("MAX_DEBT"));
        c.minDebt = uint24(vm.envUint("MIN_DEBT"));
        c.debtDecimals = uint8(vm.envUint("DEBT_DECIMALS"));
        c.collateralRatio = uint32(vm.envUint("COLLATERAL_RATIO"));
        c.ausdcIlkToWad = vm.envOr("AUSDC_ILK_TO_WAD", uint256(0));
        c.usdcIlkToWad = vm.envOr("USDC_ILK_TO_WAD", uint256(0));
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
        require(c.usdcJoin.asset() == c.usdc, "USDC join mismatch");

        // Join permissions.
        c.ausdcJoin.grantRole(IJoin.join.selector, address(c.ladle));
        c.ausdcJoin.grantRole(IJoin.exit.selector, address(c.ladle));
        c.ausdcJoin.grantRole(IJoin.exit.selector, address(c.witch));
        c.usdcJoin.grantRole(IJoin.join.selector, address(c.ladle));
        c.usdcJoin.grantRole(IJoin.exit.selector, address(c.ladle));
        c.usdcJoin.grantRole(IJoin.exit.selector, address(c.witch));

        // Assets.
        if (c.cauldron.assets(AUSDC_ID) == address(0)) c.cauldron.addAsset(AUSDC_ID, c.ausdc);
        if (c.cauldron.assets(USDC_ID) == address(0)) c.cauldron.addAsset(USDC_ID, c.usdc);

        // Normalize collateral/base amounts to 18-dec wad.
        // Optional env overrides avoid metadata calls in environments where staticcalls fail.
        if (c.ausdcIlkToWad == 0) {
            uint8 ausdcDecimals = IERC20Metadata(c.ausdc).decimals();
            require(ausdcDecimals <= 18, "Unsupported AUSDC decimals");
            c.ausdcIlkToWad = 10 ** (18 - ausdcDecimals);
        }
        if (c.usdcIlkToWad == 0) {
            uint8 usdcDecimals = IERC20Metadata(c.usdc).decimals();
            require(usdcDecimals <= 18, "Unsupported USDC decimals");
            c.usdcIlkToWad = 10 ** (18 - usdcDecimals);
        }
        c.cauldron.setIlkToWad(AUSDC_ID, c.ausdcIlkToWad);
        c.cauldron.setIlkToWad(USDC_ID, c.usdcIlkToWad);

        // Ladle join registry.
        if (address(c.ladle.joins(AUSDC_ID)) != address(c.ausdcJoin)) c.ladle.addJoin(AUSDC_ID, IJoin(address(c.ausdcJoin)));
        if (address(c.ladle.joins(USDC_ID)) != address(c.usdcJoin)) c.ladle.addJoin(USDC_ID, IJoin(address(c.usdcJoin)));

        // Oracle + risk parameters.
        c.cauldron.setLendingOracle(USDC_ID, c.lendingOracle);
        c.cauldron.setSpotOracle(USDC_ID, AUSDC_ID, c.spotOracle, c.collateralRatio);
        c.cauldron.setDebtLimits(USDC_ID, AUSDC_ID, c.maxDebt, c.minDebt, c.debtDecimals);

        vm.stopBroadcast();
    }
}

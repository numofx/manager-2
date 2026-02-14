// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import "../../src/Cauldron.sol";
import "../../src/Ladle.sol";
import "../../src/Witch.sol";
import "../../src/interfaces/IJoin.sol";
import "../../src/oracles/mento/MentoSpotOracle.sol";

/**
 * @title ConfigureUSDTKESm
 * @notice Configure USDT/KESm oracle wiring and debt limits on Celo
 *
 * Required environment variables:
 * - PRIVATE_KEY: Admin/deployer private key
 * - CELO_RPC: Celo RPC endpoint
 * - CAULDRON_ADDRESS: Deployed Cauldron address
 * - LADLE_ADDRESS: Deployed Ladle address
 * - WITCH_ADDRESS: Deployed Witch address
 * - MENTO_ORACLE_ADDRESS: Deployed MentoSpotOracle address
 * - KESM_ADDRESS: KESm token address
 * - KESM_JOIN_ADDRESS: KESm Join address
 *
 * Usage:
 * forge script script/celo/ConfigureUSDTKESm.s.sol:ConfigureUSDTKESm --rpc-url $CELO_RPC --broadcast
 */
contract ConfigureUSDTKESm is Script {
    // Asset address on Celo mainnet
    address constant USDT = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;

    // Mento rate feed IDs on Celo mainnet
    address constant MENTO_KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

    // Asset IDs (6 bytes)
    bytes6 constant KESM_ID = 0x4b45536d0000; // "KESm\0\0"
    bytes6 constant USDT_ID = 0x555344540000; // "USDT\0\0"

    // Oracle configuration (bounds are for inverted KESm per USD)
    uint256 constant KESM_MIN_PRICE = 66.67e18;   // 66.67 KESm/USD
    uint256 constant KESM_MAX_PRICE = 200e18;     // 200 KESm/USD
    uint256 constant KESM_MAX_AGE = 1 hours;
    uint256 constant KESM_MIN_NUM_RATES = 1;

    // Collateralization ratio (basis points out of 1,000,000)
    uint32 constant KESM_COLLATERAL_RATIO = 2000000; // 200%

    // Debt limits (USDT base, KESm collateral)
    uint96 constant MAX_DEBT_USDT_BASE = 10_000_000e6; // 10M USDT (6 decimals)
    uint24 constant MIN_DEBT = 100;
    uint8 constant DEBT_DECIMALS_6 = 6;

    function run() external {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        Cauldron cauldron = Cauldron(vm.envAddress("CAULDRON_ADDRESS"));
        Ladle ladle = Ladle(payable(vm.envAddress("LADLE_ADDRESS")));
        Witch witch = Witch(vm.envAddress("WITCH_ADDRESS"));
        MentoSpotOracle mentoOracle = MentoSpotOracle(vm.envAddress("MENTO_ORACLE_ADDRESS"));
        address kesm = vm.envAddress("KESM_ADDRESS");
        address kesmJoin = vm.envAddress("KESM_JOIN_ADDRESS");

        console.log("========================================");
        console.log("Configuring USDT/KESm on Celo");
        console.log("========================================");
        console.log("Cauldron:", address(cauldron));
        console.log("Ladle:", address(ladle));
        console.log("Witch:", address(witch));
        console.log("MentoOracle:", address(mentoOracle));
        console.log("Admin:", admin);
        console.log("");

        vm.startBroadcast(adminPrivateKey);

        // Grant admin permissions to broadcaster
        cauldron.grantRole(Cauldron.addAsset.selector, admin);
        cauldron.grantRole(Cauldron.setSpotOracle.selector, admin);
        cauldron.grantRole(Cauldron.setDebtLimits.selector, admin);
        cauldron.grantRole(Cauldron.setIlkToWad.selector, admin);
        ladle.grantRole(Ladle.addJoin.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.addSource.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.setSource.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.setBounds.selector, admin);

        // Add assets if missing
        if (cauldron.assets(KESM_ID) == address(0)) {
            cauldron.addAsset(KESM_ID, kesm);
        }
        if (cauldron.assets(USDT_ID) == address(0)) {
            cauldron.addAsset(USDT_ID, USDT);
        }

        // Set collateral scaling
        cauldron.setIlkToWad(USDT_ID, 1e12); // USDT has 6 decimals
        cauldron.setIlkToWad(KESM_ID, 1); // 18-dec collateral

        // Update KESm Join mapping on Ladle if needed
        if (address(ladle.joins(KESM_ID)) != kesmJoin) {
            ladle.addJoin(KESM_ID, IJoin(kesmJoin));
        }

        // Configure Mento Oracle for USDT->KESm and mirror KESm->USDT for liquidation checks
        (address rateFeedID,,,,) = mentoOracle.sources(USDT_ID, KESM_ID);
        if (rateFeedID == address(0)) {
            mentoOracle.addSource(USDT_ID, KESM_ID, MENTO_KES_USD_FEED, KESM_MAX_AGE, KESM_MIN_NUM_RATES);
        } else {
            mentoOracle.setSource(USDT_ID, KESM_ID, MENTO_KES_USD_FEED, KESM_MAX_AGE, KESM_MIN_NUM_RATES);
        }
        (address mirrorRateID,,,,) = mentoOracle.sources(KESM_ID, USDT_ID);
        if (mirrorRateID == address(0)) {
            mentoOracle.addSource(KESM_ID, USDT_ID, MENTO_KES_USD_FEED, KESM_MAX_AGE, KESM_MIN_NUM_RATES);
        } else {
            mentoOracle.setSource(KESM_ID, USDT_ID, MENTO_KES_USD_FEED, KESM_MAX_AGE, KESM_MIN_NUM_RATES);
        }
        mentoOracle.setBounds(USDT_ID, KESM_ID, KESM_MIN_PRICE, KESM_MAX_PRICE);

        // Set spot oracle in Cauldron (USDT base, KESm collateral)
        cauldron.setSpotOracle(USDT_ID, KESM_ID, mentoOracle, KESM_COLLATERAL_RATIO);

        // Set debt limits for USDT base with KESm collateral
        cauldron.setDebtLimits(USDT_ID, KESM_ID, MAX_DEBT_USDT_BASE, MIN_DEBT, DEBT_DECIMALS_6);

        vm.stopBroadcast();
    }
}

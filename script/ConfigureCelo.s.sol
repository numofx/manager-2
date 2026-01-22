// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import "../src/Cauldron.sol";
import "../src/Ladle.sol";
import "../src/Join.sol";
import "../src/Witch.sol";
import "../src/oracles/mento/MentoSpotOracle.sol";
import "../src/oracles/chainlink/ChainlinkMultiOracle.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";

/**
 * @title ConfigureCelo
 * @notice Post-deployment configuration script for Yield Protocol V2 on Celo
 * @dev This script configures permissions, assets, oracles (Mento + Chainlink), and debt limits
 *
 * Required environment variables:
 * - PRIVATE_KEY: Admin/deployer private key
 * - CELO_RPC: Celo RPC endpoint
 * - CAULDRON_ADDRESS: Deployed Cauldron address
 * - LADLE_ADDRESS: Deployed Ladle address
 * - WITCH_ADDRESS: Deployed Witch address
 * - MENTO_ORACLE_ADDRESS: Deployed MentoSpotOracle address
 * - CHAINLINK_ORACLE_ADDRESS: Deployed ChainlinkMultiOracle address
 * - CKES_JOIN_ADDRESS: Deployed cKES Join address
 * - USDT_JOIN_ADDRESS: Deployed USDT Join address
 * - CELO_JOIN_ADDRESS: Deployed CELO Join address
 *
 * Usage:
 * forge script script/ConfigureCelo.s.sol:ConfigureCelo --rpc-url $CELO_RPC --broadcast
 */
contract ConfigureCelo is Script {
    // Asset addresses on Celo mainnet
    address constant WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address constant CKES = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
    address constant USDT = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;

    // Mento rate feed IDs on Celo mainnet
    address constant MENTO_KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

    // Asset IDs (6 bytes)
    bytes6 constant CKES_ID = 0x634b45530000; // "cKES\0\0"
    bytes6 constant USDT_ID = 0x555344540000; // "USDT\0\0"
    bytes6 constant CELO_ID = 0x43454c4f0000; // "CELO\0\0"

    // Oracle configuration
    // Price bounds for cKES/USD (in 1e18 precision)
    // Example: If 1 KES = $0.0073, then bounds might be $0.005 - $0.01
    uint256 constant CKES_MIN_PRICE = 0.005e18;   // $0.005 per cKES
    uint256 constant CKES_MAX_PRICE = 0.015e18;   // $0.015 per cKES
    uint256 constant CKES_MAX_AGE = 1 hours;      // Maximum price staleness

    // Collateralization ratios (basis points out of 1,000,000)
    // Example: 150% = 1,500,000 (need $1.50 collateral per $1 borrowed)
    uint32 constant CELO_COLLATERAL_RATIO = 1500000; // 150%
    uint32 constant USDT_COLLATERAL_RATIO = 1200000; // 120%
    uint32 constant CKES_COLLATERAL_RATIO = 2000000; // 200% (higher due to volatility)

    // Debt limits
    uint96 constant MAX_DEBT_CKES_BASE = 1_000_000e18;   // 1M max when cKES is base
    uint96 constant MAX_DEBT_USDT_BASE = 10_000_000e6;   // 10M max when USDT is base (6 decimals)
    uint96 constant MAX_DEBT_CELO_BASE = 5_000_000e18;   // 5M max when CELO is base
    uint24 constant MIN_DEBT = 100;                      // Minimum debt amount
    uint8 constant DEBT_DECIMALS_18 = 18;
    uint8 constant DEBT_DECIMALS_6 = 6;

    function run() external {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        // Load deployed contract addresses from environment
        Cauldron cauldron = Cauldron(vm.envAddress("CAULDRON_ADDRESS"));
        Ladle ladle = Ladle(payable(vm.envAddress("LADLE_ADDRESS")));
        Witch witch = Witch(vm.envAddress("WITCH_ADDRESS"));
        MentoSpotOracle mentoOracle = MentoSpotOracle(vm.envAddress("MENTO_ORACLE_ADDRESS"));
        ChainlinkMultiOracle chainlinkOracle = ChainlinkMultiOracle(vm.envAddress("CHAINLINK_ORACLE_ADDRESS"));

        IJoin ckesJoin = IJoin(vm.envAddress("CKES_JOIN_ADDRESS"));
        IJoin usdtJoin = IJoin(vm.envAddress("USDT_JOIN_ADDRESS"));
        IJoin celoJoin = IJoin(vm.envAddress("CELO_JOIN_ADDRESS"));

        console.log("========================================");
        console.log("Configuring Yield Protocol V2 on Celo");
        console.log("========================================");
        console.log("Cauldron:", address(cauldron));
        console.log("Ladle:", address(ladle));
        console.log("Witch:", address(witch));
        console.log("MentoOracle:", address(mentoOracle));
        console.log("Admin:", admin);
        console.log("");

        vm.startBroadcast(adminPrivateKey);

        // ============================================================
        // Step 1: Grant Admin Permissions to Broadcaster EOA
        // ============================================================
        console.log("1. Granting admin permissions to broadcaster...");

        // Grant governance function permissions to admin EOA
        cauldron.grantRole(Cauldron.addAsset.selector, admin);
        cauldron.grantRole(Cauldron.setSpotOracle.selector, admin);
        cauldron.grantRole(Cauldron.setDebtLimits.selector, admin);
        cauldron.grantRole(Cauldron.setIlkToWad.selector, admin);
        ladle.grantRole(Ladle.addJoin.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.addSource.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.setSource.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.setBounds.selector, admin);

        console.log("   [OK] Admin permissions granted to broadcaster");
        console.log("");

        // ============================================================
        // Step 2: Grant Permissions to Protocol Contracts
        // ============================================================
        console.log("2. Granting permissions to protocol contracts...");

        // Ladle needs comprehensive permissions on Cauldron
        console.log("   Granting Ladle permissions on Cauldron...");
        cauldron.grantRole(Cauldron.build.selector, address(ladle));
        cauldron.grantRole(Cauldron.destroy.selector, address(ladle));
        cauldron.grantRole(Cauldron.tweak.selector, address(ladle));
        cauldron.grantRole(Cauldron.give.selector, address(ladle));
        cauldron.grantRole(Cauldron.pour.selector, address(ladle));
        cauldron.grantRole(Cauldron.stir.selector, address(ladle));
        cauldron.grantRole(Cauldron.roll.selector, address(ladle));

        // Witch needs liquidation permissions on Cauldron
        console.log("   Granting Witch permissions on Cauldron...");
        cauldron.grantRole(Cauldron.give.selector, address(witch));
        cauldron.grantRole(Cauldron.pour.selector, address(witch));
        cauldron.grantRole(Cauldron.slurp.selector, address(witch));

        // Ladle needs permissions on all Joins
        console.log("   Granting Ladle permissions on Joins...");
        Join(address(ckesJoin)).grantRole(IJoin.join.selector, address(ladle));
        Join(address(ckesJoin)).grantRole(IJoin.exit.selector, address(ladle));
        Join(address(usdtJoin)).grantRole(IJoin.join.selector, address(ladle));
        Join(address(usdtJoin)).grantRole(IJoin.exit.selector, address(ladle));
        Join(address(celoJoin)).grantRole(IJoin.join.selector, address(ladle));
        Join(address(celoJoin)).grantRole(IJoin.exit.selector, address(ladle));

        // Witch needs exit permissions on all Joins for liquidations
        console.log("   Granting Witch permissions on Joins...");
        Join(address(ckesJoin)).grantRole(IJoin.exit.selector, address(witch));
        Join(address(usdtJoin)).grantRole(IJoin.exit.selector, address(witch));
        Join(address(celoJoin)).grantRole(IJoin.exit.selector, address(witch));

        console.log("   [OK] Protocol permissions granted");
        console.log("");

        // ============================================================
        // Step 3: Add Assets to Cauldron
        // ============================================================
        console.log("3. Adding assets to Cauldron...");
        cauldron.addAsset(CKES_ID, CKES);
        console.log("   [OK] Added cKES");
        cauldron.addAsset(USDT_ID, USDT);
        console.log("   [OK] Added USDT");
        cauldron.addAsset(CELO_ID, WCELO);
        console.log("   [OK] Added CELO");
        console.log("");

        // ============================================================
        // Step 3a: Set Ilk WAD Scaling
        // ============================================================
        console.log("3a. Setting collateral scaling factors...");
        cauldron.setIlkToWad(USDT_ID, 1e12); // USDT has 6 decimals
        cauldron.setIlkToWad(CKES_ID, 1); // 18-dec collateral
        cauldron.setIlkToWad(CELO_ID, 1); // 18-dec collateral
        console.log("   [OK] Collateral scaling configured");
        console.log("");

        // ============================================================
        // Step 4: Register Joins with Ladle
        // ============================================================
        console.log("4. Registering Joins with Ladle...");
        ladle.addJoin(CKES_ID, IJoin(address(ckesJoin)));
        console.log("   [OK] Registered cKES Join");
        ladle.addJoin(USDT_ID, IJoin(address(usdtJoin)));
        console.log("   [OK] Registered USDT Join");
        ladle.addJoin(CELO_ID, IJoin(address(celoJoin)));
        console.log("   [OK] Registered CELO Join");
        console.log("");

        // ============================================================
        // Step 5: Configure Mento Oracle for USDT->cKES
        // ============================================================
        console.log("5. Configuring Mento Oracle...");

        // Set USDT->cKES price source from Mento (maxAge is set here)
        console.log("   Setting USDT->cKES source (Mento KES/USD feed)...");
        mentoOracle.addSource(
            USDT_ID,  // Using USDT as USD proxy
            CKES_ID,
            MENTO_KES_USD_FEED,
            CKES_MAX_AGE, // Max age: 1 hour
            0             // minNumRates (0 = no minimum enforced)
        );
        console.log("   [OK] Set USDT->cKES source with staleness check (max age: 1 hour)");

        // Set sanity bounds for cKES/USD
        console.log("   Setting USDT->cKES sanity bounds ($0.005 - $0.015)...");
        mentoOracle.setBounds(USDT_ID, CKES_ID, CKES_MIN_PRICE, CKES_MAX_PRICE);

        console.log("   [OK] Mento Oracle configured for USDT->cKES");
        console.log("");

        // ============================================================
        // Step 6: Set Spot Oracles in Cauldron
        // ============================================================
        console.log("6. Setting spot oracles in Cauldron...");

        // Set USDT/cKES spot oracle (for cKES collateral, USDT base)
        console.log("   Setting USDT/cKES spot oracle (200% ratio)...");
        cauldron.setSpotOracle(
            USDT_ID,              // base (what you borrow)
            CKES_ID,              // ilk (collateral)
            mentoOracle,          // oracle
            CKES_COLLATERAL_RATIO // 200% collateralization
        );

        console.log("   [OK] Spot oracles configured");
        console.log("   NOTE: Add CELO/USD and USDT/CELO oracles when available");
        console.log("");

        // ============================================================
        // Step 7: Set Debt Limits
        // ============================================================
        console.log("7. Setting debt limits...");

        // Set debt limits for USDT base with cKES collateral
        console.log("   Setting USDT/cKES debt limits (max: 10M USDT)...");
        cauldron.setDebtLimits(
            USDT_ID,              // base
            CKES_ID,              // ilk (collateral)
            MAX_DEBT_USDT_BASE,
            MIN_DEBT,
            DEBT_DECIMALS_6       // USDT has 6 decimals
        );

        console.log("   [OK] Debt limits configured");
        console.log("");

        // ============================================================
        // Step 8: Configure Ilks (Approved Collateral)
        // ============================================================
        console.log("8. Adding approved collateral (ilks)...");

        // Note: addIlk is typically called when adding a series
        // This will be done when deploying FYTokens
        console.log("   Ilks will be added when creating series (FYToken deployment)");
        console.log("");

        vm.stopBroadcast();

        // ============================================================
        // Log Configuration Summary
        // ============================================================
        console.log("========================================");
        console.log("CONFIGURATION COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Permissions:");
        console.log("  [OK] Ladle can manage vaults in Cauldron");
        console.log("  [OK] Witch can liquidate vaults");
        console.log("  [OK] Ladle and Witch can move assets through Joins");
        console.log("");
        console.log("Assets:");
        console.log("  [OK] cKES (", CKES, ")");
        console.log("  [OK] USDT (", USDT, ")");
        console.log("  [OK] CELO (", WCELO, ")");
        console.log("");
        console.log("Oracles:");
        console.log("  [OK] USDT->cKES via Mento (KES/USD feed)");
        console.log("    - Max age: 1 hour");
        console.log("    - Bounds: $0.005 - $0.015");
        console.log("    - Collateral ratio: 200%");
        console.log("");
        console.log("Debt Limits:");
        console.log("  [OK] USDT base / cKES collateral: 10M USDT max");
        console.log("");
        console.log("========================================");
        console.log("NEXT STEPS:");
        console.log("========================================");
        console.log("1. Deploy FYToken contracts for each series:");
        console.log("   - Create series with different maturity dates");
        console.log("   - Call cauldron.addSeries() for each");
        console.log("   - Call cauldron.addIlks() to enable collateral types");
        console.log("");
        console.log("2. Configure additional oracle pairs:");
        console.log("   - CELO/USD (via Chainlink or Mento)");
        console.log("   - USDT/CELO (composite oracle)");
        console.log("   - Set corresponding spot oracles in Cauldron");
        console.log("");
        console.log("3. Configure Witch liquidation parameters:");
        console.log("   - Set auction parameters (duration, initial offer, etc.)");
        console.log("   - Configure auctioneer rewards");
        console.log("");
        console.log("4. Test thoroughly on Alfajores testnet:");
        console.log("   - Test vault creation");
        console.log("   - Test borrowing");
        console.log("   - Test liquidations");
        console.log("   - Verify oracle price feeds");
        console.log("");
        console.log("5. Set up monitoring:");
        console.log("   - Monitor oracle staleness");
        console.log("   - Track vault health ratios");
        console.log("   - Alert on liquidation opportunities");
        console.log("========================================");
    }
}

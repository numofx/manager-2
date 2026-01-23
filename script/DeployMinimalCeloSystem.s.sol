// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import "../src/Cauldron.sol";
import "../src/Ladle.sol";
import "../src/Join.sol";
import "../src/Witch.sol";
import "../src/FYToken.sol";
import "../src/oracles/mento/MentoSpotOracle.sol";
import "../src/oracles/mento/ISortedOracles.sol";
import "../src/oracles/chainlink/AggregatorV3Interface.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";

/**
 * @title DeployMinimalCeloSystem
 * @notice Minimal deployment for Yield Protocol V2 on Celo
 * @dev Configuration:
 *      - Collateral: USDT
 *      - Base (borrow/lend): KESm
 *      - Oracle: Mento SortedOracles (returns KESm per USDT, 1e18)
 *
 * Usage (Celo Mainnet):
 *   forge script script/DeployMinimalCeloSystem.s.sol:DeployMinimalCeloSystem \
 *     --rpc-url $CELO_RPC \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --slow
 *
 * Usage (Alfajores Testnet - RECOMMENDED FIRST):
 *   forge script script/DeployMinimalCeloSystem.s.sol:DeployMinimalCeloSystem \
 *     --rpc-url https://alfajores-forno.celo-testnet.org \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployMinimalCeloSystem is Script {
    // Celo mainnet addresses
    address constant WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address constant KESM = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
    address constant USDT = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;

    // Mento protocol addresses
    address constant MENTO_SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
    address constant MENTO_KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;
    address constant USDT_USD_FEED = 0x5e37AF40A7A344ec9b03CCD34a250F3dA9a20B02;

    // Asset IDs (6 bytes)
    bytes6 constant KESM_ID = 0x634b45530000; // "KESm\0\0" - BASE ASSET
    bytes6 constant USDT_ID = 0x555344540000; // "USDT\0\0" - COLLATERAL

    // Oracle configuration
    uint256 constant MAX_AGE = 3600;          // 1 hour staleness limit
    uint256 constant MIN_PRICE = 66.67e18;    // Min KESm/USD (inverse of $0.015)
    uint256 constant MAX_PRICE = 200e18;      // Max KESm/USD (inverse of $0.005)

    // Collateralization: 200% (need $2 USDT collateral per 1 KESm borrowed)
    uint32 constant COLLATERAL_RATIO = 2000000; // 200% in basis points (out of 1M)

    // Debt limits
    uint96 constant MAX_DEBT = 1_000_000e18;  // 1M KESm max debt
    uint24 constant MIN_DEBT = 100;           // Minimum debt
    uint8 constant DEBT_DECIMALS = 18;        // KESm has 18 decimals

    // Deployed contracts
    Cauldron public cauldron;
    Ladle public ladle;
    Witch public witch;
    MentoSpotOracle public mentoOracle;
    Join public kesmJoin;
    Join public usdtJoin;

    function run() external {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(adminPrivateKey);

        vm.startBroadcast(adminPrivateKey);

        // ============================================================
        // STEP 1: Deploy Core Contracts
        // ============================================================

        // Deploy Cauldron (accounting ledger)
        cauldron = new Cauldron();

        // Deploy Ladle (user gateway)
        ladle = new Ladle(ICauldron(address(cauldron)), IWETH9(WCELO));

        // Deploy Witch (liquidation engine)
        witch = new Witch(ICauldron(address(cauldron)), ILadle(address(ladle)));

        // ============================================================
        // STEP 2: Deploy Oracle
        // ============================================================

        // Deploy MentoSpotOracle
        // Returns: KESm per USDT (≈ KESm/USD), scaled to 1e18
        mentoOracle = new MentoSpotOracle(
            ISortedOracles(MENTO_SORTED_ORACLES),
            AggregatorV3Interface(USDT_USD_FEED)
        );

        // ============================================================
        // STEP 3: Deploy Join Contracts
        // ============================================================

        // KESm Join (base asset - what you borrow/lend)
        kesmJoin = new Join(KESM);

        // USDT Join (collateral - what backs your borrows)
        usdtJoin = new Join(USDT);

        // ============================================================
        // STEP 4: Grant Permissions to Protocol Contracts
        // ============================================================

        // Ladle needs permissions on Cauldron
        cauldron.grantRole(Cauldron.build.selector, address(ladle));
        cauldron.grantRole(Cauldron.destroy.selector, address(ladle));
        cauldron.grantRole(Cauldron.tweak.selector, address(ladle));
        cauldron.grantRole(Cauldron.give.selector, address(ladle));
        cauldron.grantRole(Cauldron.pour.selector, address(ladle));
        cauldron.grantRole(Cauldron.stir.selector, address(ladle));
        cauldron.grantRole(Cauldron.roll.selector, address(ladle));

        // Witch needs permissions on Cauldron
        cauldron.grantRole(Cauldron.give.selector, address(witch));
        cauldron.grantRole(Cauldron.pour.selector, address(witch));
        cauldron.grantRole(Cauldron.slurp.selector, address(witch));

        // Ladle needs permissions on Joins
        Join(address(kesmJoin)).grantRole(IJoin.join.selector, address(ladle));
        Join(address(kesmJoin)).grantRole(IJoin.exit.selector, address(ladle));
        Join(address(usdtJoin)).grantRole(IJoin.join.selector, address(ladle));
        Join(address(usdtJoin)).grantRole(IJoin.exit.selector, address(ladle));

        // Witch needs permissions on Joins
        Join(address(kesmJoin)).grantRole(IJoin.exit.selector, address(witch));
        Join(address(usdtJoin)).grantRole(IJoin.exit.selector, address(witch));

        // ============================================================
        // STEP 5: Grant Admin Permissions to Broadcaster EOA
        // ============================================================
        // Required for governance calls made by this script

        cauldron.grantRole(Cauldron.addAsset.selector, admin);
        cauldron.grantRole(Cauldron.setSpotOracle.selector, admin);
        cauldron.grantRole(Cauldron.setDebtLimits.selector, admin);
        cauldron.grantRole(Cauldron.setIlkToWad.selector, admin);
        ladle.grantRole(Ladle.addJoin.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.addSource.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.setSource.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.setBounds.selector, admin);

        // ============================================================
        // STEP 6: Add Assets to Cauldron
        // ============================================================

        // KESm is the BASE asset (what you borrow/lend)
        cauldron.addAsset(KESM_ID, KESM);

        // USDT is the COLLATERAL asset (what backs borrows)
        cauldron.addAsset(USDT_ID, USDT);

        // Scale collateral to WAD (1e18)
        cauldron.setIlkToWad(USDT_ID, 1e12); // USDT has 6 decimals
        cauldron.setIlkToWad(KESM_ID, 1); // 18-dec collateral

        // ============================================================
        // STEP 7: Register Joins with Ladle
        // ============================================================

        ladle.addJoin(KESM_ID, IJoin(address(kesmJoin)));
        ladle.addJoin(USDT_ID, IJoin(address(usdtJoin)));

        // ============================================================
        // STEP 8: Configure Oracle
        // ============================================================

        // Set USDT->KESm source (returns KESm per USDT, 1e18)
        // Uses Mento KES/USD feed with INVERSION
        mentoOracle.addSource(
            USDT_ID,              // base (USDT collateral)
            KESM_ID,              // quote (KESm base asset)
            MENTO_KES_USD_FEED,   // Mento feed (returns USD/KES, will be inverted)
            MAX_AGE,              // 3600 seconds staleness limit
            0                     // minNumRates (0 = no minimum enforced)
        );

        // Set sanity bounds for inverted price (KESm per USD)
        mentoOracle.setBounds(
            USDT_ID,              // base (USDT collateral)
            KESM_ID,              // quote (KESm base asset)
            MIN_PRICE,            // 66.67 KESm/USD min
            MAX_PRICE             // 200 KESm/USD max
        );

        // Set spot oracle in Cauldron
        // This enables USDT as collateral for KESm borrowing
        cauldron.setSpotOracle(
            KESM_ID,              // base (what you borrow)
            USDT_ID,              // ilk (collateral)
            mentoOracle,          // oracle (returns KESm per USDT)
            COLLATERAL_RATIO      // 200% collateralization ratio
        );

        // ============================================================
        // STEP 9: Set Debt Limits
        // ============================================================

        // Set max debt for KESm base with USDT collateral
        cauldron.setDebtLimits(
            KESM_ID,              // base (KESm)
            USDT_ID,              // ilk (USDT collateral)
            MAX_DEBT,             // 1M KESm max
            MIN_DEBT,
            DEBT_DECIMALS
        );

        vm.stopBroadcast();

        // ============================================================
        // Log Deployment Summary
        // ============================================================

        // Note: Using assembly to avoid script compilation issues
        // In actual deployment, use console.log if available
    }

    // Helper to get deployed addresses for configuration
    function getDeployedAddresses() external view returns (
        address cauldron_,
        address ladle_,
        address witch_,
        address mentoOracle_,
        address kesmJoin_,
        address usdtJoin_
    ) {
        return (
            address(cauldron),
            address(ladle),
            address(witch),
            address(mentoOracle),
            address(kesmJoin),
            address(usdtJoin)
        );
    }
}

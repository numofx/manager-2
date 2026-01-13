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
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";

/**
 * @title DeployMinimalCeloSystem
 * @notice Minimal deployment for Yield Protocol V2 on Celo
 * @dev Configuration:
 *      - Collateral: USDT
 *      - Base (borrow/lend): cKES
 *      - Oracle: Mento SortedOracles (returns cKES per USDT, 1e18)
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
    address constant CKES = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
    address constant USDT = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;

    // Mento protocol addresses
    address constant MENTO_SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
    address constant MENTO_KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

    // Asset IDs (6 bytes)
    bytes6 constant CKES_ID = 0x634b45530000; // "cKES\0\0" - BASE ASSET
    bytes6 constant USDT_ID = 0x555344540000; // "USDT\0\0" - COLLATERAL

    // Oracle configuration
    uint256 constant MAX_AGE = 3600;          // 1 hour staleness limit
    uint256 constant MIN_PRICE = 66.67e18;    // Min cKES/USD (inverse of $0.015)
    uint256 constant MAX_PRICE = 200e18;      // Max cKES/USD (inverse of $0.005)

    // Collateralization: 200% (need $2 USDT collateral per 1 cKES borrowed)
    uint32 constant COLLATERAL_RATIO = 2000000; // 200% in basis points (out of 1M)

    // Debt limits
    uint96 constant MAX_DEBT = 1_000_000e18;  // 1M cKES max debt
    uint24 constant MIN_DEBT = 100;           // Minimum debt
    uint8 constant DEBT_DECIMALS = 18;        // cKES has 18 decimals

    // Deployed contracts
    Cauldron public cauldron;
    Ladle public ladle;
    Witch public witch;
    MentoSpotOracle public mentoOracle;
    Join public ckesJoin;
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
        // Returns: cKES per USDT (≈ cKES/USD), scaled to 1e18
        mentoOracle = new MentoSpotOracle(ISortedOracles(MENTO_SORTED_ORACLES));

        // ============================================================
        // STEP 3: Deploy Join Contracts
        // ============================================================

        // cKES Join (base asset - what you borrow/lend)
        ckesJoin = new Join(CKES);

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
        Join(address(ckesJoin)).grantRole(IJoin.join.selector, address(ladle));
        Join(address(ckesJoin)).grantRole(IJoin.exit.selector, address(ladle));
        Join(address(usdtJoin)).grantRole(IJoin.join.selector, address(ladle));
        Join(address(usdtJoin)).grantRole(IJoin.exit.selector, address(ladle));

        // Witch needs permissions on Joins
        Join(address(ckesJoin)).grantRole(IJoin.exit.selector, address(witch));
        Join(address(usdtJoin)).grantRole(IJoin.exit.selector, address(witch));

        // ============================================================
        // STEP 5: Grant Admin Permissions to Broadcaster EOA
        // ============================================================
        // Required for governance calls made by this script

        cauldron.grantRole(Cauldron.addAsset.selector, admin);
        cauldron.grantRole(Cauldron.setSpotOracle.selector, admin);
        cauldron.grantRole(Cauldron.setDebtLimits.selector, admin);
        ladle.grantRole(Ladle.addJoin.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.addSource.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.setSource.selector, admin);
        mentoOracle.grantRole(MentoSpotOracle.setBounds.selector, admin);

        // ============================================================
        // STEP 6: Add Assets to Cauldron
        // ============================================================

        // cKES is the BASE asset (what you borrow/lend)
        cauldron.addAsset(CKES_ID, CKES);

        // USDT is the COLLATERAL asset (what backs borrows)
        cauldron.addAsset(USDT_ID, USDT);

        // ============================================================
        // STEP 7: Register Joins with Ladle
        // ============================================================

        ladle.addJoin(CKES_ID, IJoin(address(ckesJoin)));
        ladle.addJoin(USDT_ID, IJoin(address(usdtJoin)));

        // ============================================================
        // STEP 8: Configure Oracle
        // ============================================================

        // Set USDT->cKES source (returns cKES per USDT, 1e18)
        // Uses Mento KES/USD feed with INVERSION
        mentoOracle.addSource(
            USDT_ID,              // base (USDT collateral)
            CKES_ID,              // quote (cKES base asset)
            MENTO_KES_USD_FEED,   // Mento feed (returns USD/KES, will be inverted)
            MAX_AGE               // 3600 seconds staleness limit
        );

        // Set sanity bounds for inverted price (cKES per USD)
        mentoOracle.setBounds(
            USDT_ID,              // base (USDT collateral)
            CKES_ID,              // quote (cKES base asset)
            MIN_PRICE,            // 66.67 cKES/USD min
            MAX_PRICE             // 200 cKES/USD max
        );

        // Set spot oracle in Cauldron
        // This enables USDT as collateral for cKES borrowing
        cauldron.setSpotOracle(
            CKES_ID,              // base (what you borrow)
            USDT_ID,              // ilk (collateral)
            mentoOracle,          // oracle (returns cKES per USDT)
            COLLATERAL_RATIO      // 200% collateralization ratio
        );

        // ============================================================
        // STEP 9: Set Debt Limits
        // ============================================================

        // Set max debt for cKES base with USDT collateral
        cauldron.setDebtLimits(
            CKES_ID,              // base (cKES)
            USDT_ID,              // ilk (USDT collateral)
            MAX_DEBT,             // 1M cKES max
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
        address ckesJoin_,
        address usdtJoin_
    ) {
        return (
            address(cauldron),
            address(ladle),
            address(witch),
            address(mentoOracle),
            address(ckesJoin),
            address(usdtJoin)
        );
    }
}

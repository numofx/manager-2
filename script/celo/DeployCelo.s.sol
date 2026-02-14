// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import "../../src/Cauldron.sol";
import "../../src/Ladle.sol";
import "../../src/Join.sol";
import "../../src/Witch.sol";
import "../../src/FYToken.sol";
import "../../src/oracles/mento/MentoSpotOracle.sol";
import "../../src/oracles/mento/ISortedOracles.sol";
import "../../src/oracles/chainlink/AggregatorV3Interface.sol";
import "../../src/oracles/chainlink/ChainlinkMultiOracle.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";

/**
 * @title DeployCelo
 * @notice Deployment script for Yield Protocol V2 core contracts on Celo
 * @dev This script deploys the core system with KESm and USDT support
 *
 * Required environment variables:
 * - PRIVATE_KEY: Deployer private key
 * - CELO_RPC: Celo RPC endpoint
 *
 * Usage:
 * forge script script/celo/DeployCelo.s.sol:DeployCelo --rpc-url $CELO_RPC --broadcast --verify --slow
 */
contract DeployCelo is Script {
    // Celo mainnet addresses
    address constant WCELO = 0x471EcE3750Da237f93B8E339c536989b8978a438;
    address constant KESM = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;
    address constant USDT = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;

    // Mento protocol addresses on Celo mainnet
    address constant MENTO_SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
    address constant MENTO_KES_USD_FEED = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;
    address constant USDT_USD_FEED = 0x5e37AF40A7A344ec9b03CCD34a250F3dA9a20B02;

    // Asset IDs (6 bytes)
    bytes6 constant KESM_ID = 0x634b45530000; // "KESm\0\0"
    bytes6 constant USDT_ID = 0x555344540000; // "USDT\0\0"
    bytes6 constant CELO_ID = 0x43454c4f0000; // "CELO\0\0"

    // Deployed contracts (stored for logging)
    Cauldron public cauldron;
    Ladle public ladle;
    Witch public witch;
    MentoSpotOracle public mentoOracle;
    ChainlinkMultiOracle public chainlinkOracle;
    Join public kesmJoin;
    Join public usdtJoin;
    Join public celoJoin;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("Deploying Yield Protocol V2 on Celo");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ============================================================
        // Step 1: Deploy Core Accounting (Cauldron)
        // ============================================================
        console.log("1. Deploying Cauldron...");
        cauldron = new Cauldron();
        console.log("   Cauldron deployed at:", address(cauldron));
        console.log("");

        // ============================================================
        // Step 2: Deploy Ladle (User Gateway)
        // ============================================================
        console.log("2. Deploying Ladle...");
        ladle = new Ladle(ICauldron(address(cauldron)), IWETH9(WCELO));
        console.log("   Ladle deployed at:", address(ladle));
        console.log("");

        // ============================================================
        // Step 3: Deploy Witch (Liquidation Engine)
        // ============================================================
        console.log("3. Deploying Witch...");
        witch = new Witch(ICauldron(address(cauldron)), ILadle(address(ladle)));
        console.log("   Witch deployed at:", address(witch));
        console.log("");

        // ============================================================
        // Step 4: Deploy Oracles
        // ============================================================
        console.log("4. Deploying Oracles...");

        console.log("   4a. Deploying MentoSpotOracle...");
        mentoOracle = new MentoSpotOracle(
            ISortedOracles(MENTO_SORTED_ORACLES),
            AggregatorV3Interface(USDT_USD_FEED)
        );
        console.log("       MentoSpotOracle deployed at:", address(mentoOracle));

        console.log("   4b. Deploying ChainlinkMultiOracle...");
        chainlinkOracle = new ChainlinkMultiOracle();
        console.log("       ChainlinkMultiOracle deployed at:", address(chainlinkOracle));
        console.log("");

        // ============================================================
        // Step 5: Deploy Join Contracts (one per asset)
        // ============================================================
        console.log("5. Deploying Join contracts...");

        console.log("   5a. Deploying KESm Join...");
        kesmJoin = new Join(KESM);
        console.log("       KESm Join deployed at:", address(kesmJoin));

        console.log("   5b. Deploying USDT Join...");
        usdtJoin = new Join(USDT);
        console.log("       USDT Join deployed at:", address(usdtJoin));

        console.log("   5c. Deploying CELO Join...");
        celoJoin = new Join(WCELO);
        console.log("       CELO Join deployed at:", address(celoJoin));
        console.log("");

        vm.stopBroadcast();

        // ============================================================
        // Log deployment summary
        // ============================================================
        console.log("========================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("========================================");
        console.log("");
        console.log("Core Contracts:");
        console.log("  Cauldron:", address(cauldron));
        console.log("  Ladle:", address(ladle));
        console.log("  Witch:", address(witch));
        console.log("");
        console.log("Oracles:");
        console.log("  MentoSpotOracle:", address(mentoOracle));
        console.log("  ChainlinkMultiOracle:", address(chainlinkOracle));
        console.log("");
        console.log("Join Contracts:");
        console.log("  KESm Join:", address(kesmJoin));
        console.log("  USDT Join:", address(usdtJoin));
        console.log("  CELO Join:", address(celoJoin));
        console.log("");
        console.log("Asset Addresses:");
        console.log("  KESm:", KESM);
        console.log("  USDT:", USDT);
        console.log("  wCELO:", WCELO);
        console.log("");
        console.log("========================================");
        console.log("NEXT STEPS:");
        console.log("========================================");
        console.log("1. Run the configuration script:");
        console.log("   forge script script/celo/ConfigureCelo.s.sol:ConfigureCelo --rpc-url $CELO_RPC --broadcast");
        console.log("");
        console.log("2. Configure Chainlink oracle price feeds");
        console.log("3. Set collateralization ratios");
        console.log("4. Set debt limits");
        console.log("5. Deploy FYToken contracts for each series");
        console.log("========================================");
    }
}

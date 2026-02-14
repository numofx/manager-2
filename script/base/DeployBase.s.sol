// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import "../../src/Cauldron.sol";
import "../../src/Ladle.sol";
import "../../src/Join.sol";
import "../../src/Witch.sol";
import "../../src/oracles/chainlink/ChainlinkMultiOracle.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";

/**
 * @title DeployBase
 * @notice Deployment script for Yield Protocol V2 core contracts on Base
 *
 * Required environment variables:
 * - PRIVATE_KEY: Deployer private key
 * - BASE_RPC: Base RPC endpoint
 *
 * Usage:
 * forge script script/base/DeployBase.s.sol:DeployBase --rpc-url $BASE_RPC --broadcast --verify --slow
 */
contract DeployBase is Script {
    // Base mainnet wrapped native token (used by Ladle)
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // Asset IDs (6 bytes)
    bytes6 constant AUSDC_ID = 0x615553444300; // "aUSDC\0"
    bytes6 constant CNGN_ID = 0x634e474e0000; // "cNGN\0\0"

    // Deployed contracts (stored for logging)
    Cauldron public cauldron;
    Ladle public ladle;
    Witch public witch;
    ChainlinkMultiOracle public chainlinkOracle;
    Join public ausdcJoin;
    Join public cngnJoin;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address ausdc = vm.envAddress("AUSDC_ADDRESS");
        address cngn = vm.envAddress("CNGN_ADDRESS");

        console.log("========================================");
        console.log("Deploying Yield Protocol V2 on Base");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("aUSDC:", ausdc);
        console.log("cNGN:", cngn);
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
        ladle = new Ladle(ICauldron(address(cauldron)), IWETH9(WETH));
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
        chainlinkOracle = new ChainlinkMultiOracle();
        console.log("   ChainlinkMultiOracle deployed at:", address(chainlinkOracle));
        console.log("");

        // ============================================================
        // Step 5: Deploy Join Contracts
        // ============================================================
        console.log("5. Deploying Join contracts...");

        console.log("   5a. Deploying aUSDC Join...");
        ausdcJoin = new Join(ausdc);
        console.log("       aUSDC Join deployed at:", address(ausdcJoin));

        console.log("   5b. Deploying cNGN Join...");
        cngnJoin = new Join(cngn);
        console.log("       cNGN Join deployed at:", address(cngnJoin));
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
        console.log("  ChainlinkMultiOracle:", address(chainlinkOracle));
        console.log("");
        console.log("Join Contracts:");
        console.log("  aUSDC Join:", address(ausdcJoin));
        console.log("  cNGN Join:", address(cngnJoin));
        console.log("");
        console.log("Asset Addresses:");
        console.log("  aUSDC:", ausdc);
        console.log("  cNGN:", cngn);
        console.log("");
        console.log("Asset IDs:");
        console.log("  AUSDC_ID:", vm.toString(bytes32(AUSDC_ID)));
        console.log("  CNGN_ID:", vm.toString(bytes32(CNGN_ID)));
        console.log("");
        console.log("========================================");
        console.log("NEXT STEPS:");
        console.log("========================================");
        console.log("1. Grant permissions (Ladle/Witch/admin roles)");
        console.log("2. Add assets and register joins");
        console.log("3. Configure Chainlink oracle sources and spot ratios");
        console.log("4. Set debt limits");
        console.log("5. Deploy FYToken contracts for each series");
        console.log("========================================");
    }
}

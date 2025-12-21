#!/bin/bash
# Deployment script for Yield Protocol V2 on Celo
# Configuration:
#   - Base (borrow/lend): cKES
#   - Collateral: USDT
#   - Oracle: Mento (returns cKES per USDT)
# Run this after setting up your .env file

set -e  # Exit on error

echo "========================================"
echo "Yield Protocol V2 - Celo Deployment"
echo "Base Asset: cKES (borrow/lend)"
echo "Collateral: USDT"
echo "========================================"
echo ""

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found!"
    echo "Please create .env from .env.example and configure it."
    exit 1
fi

source .env

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set in .env"
    exit 1
fi

if [ -z "$CELO_RPC" ]; then
    echo "Error: CELO_RPC not set in .env"
    exit 1
fi

echo "Using RPC: $CELO_RPC"
echo ""

# Addresses
WCELO="0x471EcE3750Da237f93B8E339c536989b8978a438"
CKES="0x456a3D042C0DbD3db53D5489e98dFb038553B0d0"
USDT="0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e"
MENTO_SORTED_ORACLES="0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33"

echo "Step 1: Deploying Cauldron..."
CAULDRON_ADDRESS=$(forge create src/Cauldron.sol:Cauldron \
    --rpc-url $CELO_RPC \
    --private-key $PRIVATE_KEY \
    --json | jq -r '.deployedTo')
echo "Cauldron deployed at: $CAULDRON_ADDRESS"
echo ""

echo "Step 2: Deploying Ladle..."
LADLE_ADDRESS=$(forge create src/Ladle.sol:Ladle \
    --rpc-url $CELO_RPC \
    --private-key $PRIVATE_KEY \
    --constructor-args $CAULDRON_ADDRESS $WCELO \
    --json | jq -r '.deployedTo')
echo "Ladle deployed at: $LADLE_ADDRESS"
echo ""

echo "Step 3: Deploying Witch..."
WITCH_ADDRESS=$(forge create src/Witch.sol:Witch \
    --rpc-url $CELO_RPC \
    --private-key $PRIVATE_KEY \
    --constructor-args $CAULDRON_ADDRESS $LADLE_ADDRESS \
    --json | jq -r '.deployedTo')
echo "Witch deployed at: $WITCH_ADDRESS"
echo ""

echo "Step 4: Deploying MentoSpotOracle..."
MENTO_ORACLE_ADDRESS=$(forge create src/oracles/mento/MentoSpotOracle.sol:MentoSpotOracle \
    --rpc-url $CELO_RPC \
    --private-key $PRIVATE_KEY \
    --constructor-args $MENTO_SORTED_ORACLES \
    --json | jq -r '.deployedTo')
echo "MentoSpotOracle deployed at: $MENTO_ORACLE_ADDRESS"
echo ""

echo "Step 5: Deploying ChainlinkMultiOracle..."
CHAINLINK_ORACLE_ADDRESS=$(forge create src/oracles/chainlink/ChainlinkMultiOracle.sol:ChainlinkMultiOracle \
    --rpc-url $CELO_RPC \
    --private-key $PRIVATE_KEY \
    --json | jq -r '.deployedTo')
echo "ChainlinkMultiOracle deployed at: $CHAINLINK_ORACLE_ADDRESS"
echo ""

echo "Step 6: Deploying Join contracts..."
echo "   6a. Deploying cKES Join (base asset)..."
CKES_JOIN_ADDRESS=$(forge create src/Join.sol:Join \
    --rpc-url $CELO_RPC \
    --private-key $PRIVATE_KEY \
    --constructor-args $CKES \
    --json | jq -r '.deployedTo')
echo "   cKES Join (BASE) deployed at: $CKES_JOIN_ADDRESS"

echo "   6b. Deploying USDT Join (collateral)..."
USDT_JOIN_ADDRESS=$(forge create src/Join.sol:Join \
    --rpc-url $CELO_RPC \
    --private-key $PRIVATE_KEY \
    --constructor-args $USDT \
    --json | jq -r '.deployedTo')
echo "   USDT Join (COLLATERAL) deployed at: $USDT_JOIN_ADDRESS"
echo ""

echo "========================================"
echo "DEPLOYMENT COMPLETE!"
echo "========================================"
echo ""
echo "Deployed Addresses:"
echo "Core Contracts:"
echo "  Cauldron: $CAULDRON_ADDRESS"
echo "  Ladle: $LADLE_ADDRESS"
echo "  Witch: $WITCH_ADDRESS"
echo ""
echo "Oracles:"
echo "  MentoSpotOracle (cKES/USDT): $MENTO_ORACLE_ADDRESS"
echo ""
echo "Join Contracts:"
echo "  cKES Join (BASE): $CKES_JOIN_ADDRESS"
echo "  USDT Join (COLLATERAL): $USDT_JOIN_ADDRESS"
echo ""
echo "Configuration:"
echo "  Base Asset: cKES (what you borrow/lend)"
echo "  Collateral: USDT (what backs your borrows)"
echo "  Oracle Direction: cKES per USDT (1e18)"
echo ""
echo "Add these to your .env file:"
echo "CAULDRON_ADDRESS=$CAULDRON_ADDRESS"
echo "LADLE_ADDRESS=$LADLE_ADDRESS"
echo "WITCH_ADDRESS=$WITCH_ADDRESS"
echo "MENTO_ORACLE_ADDRESS=$MENTO_ORACLE_ADDRESS"
echo "CHAINLINK_ORACLE_ADDRESS=$CHAINLINK_ORACLE_ADDRESS"
echo "CKES_JOIN_ADDRESS=$CKES_JOIN_ADDRESS"
echo "USDT_JOIN_ADDRESS=$USDT_JOIN_ADDRESS"
echo ""
echo "Next Steps:"
echo "1. Verify oracle is working: cast call $MENTO_ORACLE_ADDRESS 'peek(bytes32,bytes32,uint256)' ..."
echo "2. Deploy fyToken series (fycKES) with maturity dates"
echo "3. Add series to Cauldron and enable USDT as approved collateral (ilk)"
echo "4. Test vault creation and borrowing on testnet first!"

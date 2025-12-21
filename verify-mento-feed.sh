#!/bin/bash
# READ-ONLY verification of Mento oracle feed direction
# NO STATE CHANGES - only reads chain data

set -e

# Configuration
SORTED_ORACLES="${SORTED_ORACLES:-0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33}"
MENTO_FEED_ID="${MENTO_FEED_ID:-0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169}"
CELO_RPC="${CELO_RPC:-https://forno.celo.org}"

echo "========================================"
echo "MENTO ORACLE FEED VERIFICATION"
echo "========================================"
echo ""
echo "SortedOracles: $SORTED_ORACLES"
echo "Feed ID: $MENTO_FEED_ID"
echo "RPC: $CELO_RPC"
echo ""

# Call medianRate(address) -> (uint256 rate, uint256 updateTime)
echo "Fetching median rate from Mento..."
RESULT=$(cast call $SORTED_ORACLES \
  "medianRate(address)(uint256,uint256)" \
  $MENTO_FEED_ID \
  --rpc-url $CELO_RPC)

# Parse result (two uint256 values)
RATE=$(echo $RESULT | awk '{print $1}')
UPDATE_TIME=$(echo $RESULT | awk '{print $2}')

echo ""
echo "Raw Data:"
echo "  Rate (hex): $RATE"
echo "  Update Time: $UPDATE_TIME"

# Convert hex to decimal
RATE_DEC=$(cast --to-dec $RATE)
UPDATE_TIME_DEC=$(cast --to-dec $UPDATE_TIME)
CURRENT_TIME=$(date +%s)
AGE=$((CURRENT_TIME - UPDATE_TIME_DEC))

echo ""
echo "  Rate (decimal): $RATE_DEC"
echo "  Update Time (decimal): $UPDATE_TIME_DEC"
echo "  Current Time: $CURRENT_TIME"
echo "  Age (seconds): $AGE"
echo ""

# Analyze magnitude
# Mento uses 1e24 precision
# If USD per KES: rate ≈ 0.0073 * 1e24 = 7.3e21 (small number)
# If KES per USD: rate ≈ 137 * 1e24 = 1.37e26 (large number)

echo "========================================"
echo "ANALYSIS:"
echo "========================================"
echo ""

# Calculate order of magnitude
DIGITS=${#RATE_DEC}

echo "Rate has $DIGITS digits"
echo ""

# Interpretation A: USD per KES
# Scale to 6 decimals (dollars and cents): rate / 1e18
USD_PER_KES=$(echo "scale=6; $RATE_DEC / 1000000000000000000" | bc)
echo "Interpretation A: USD per 1 KES"
echo "  Scaled value: \$$USD_PER_KES"

# Check plausibility
if (( $(echo "$USD_PER_KES < 0.02" | bc -l) )); then
    echo "  ✓ PLAUSIBLE: KES typically trades for < \$0.02"
    LIKELY_A="yes"
else
    echo "  ✗ IMPLAUSIBLE: KES worth > \$0.02 unlikely"
    LIKELY_A="no"
fi
echo ""

# Interpretation B: KES per USD
# Scale to integer: rate / 1e24
KES_PER_USD=$(echo "scale=2; $RATE_DEC / 1000000000000000000000000" | bc)
echo "Interpretation B: KES per 1 USD"
echo "  Scaled value: $KES_PER_USD KES"

# Check plausibility (USD typically = 100-150 KES)
if (( $(echo "$KES_PER_USD > 50 && $KES_PER_USD < 200" | bc -l) )); then
    echo "  ✓ PLAUSIBLE: USD typically = 100-150 KES"
    LIKELY_B="yes"
else
    echo "  ? UNCERTAIN: Value outside typical range"
    LIKELY_B="maybe"
fi
echo ""

# Determine direction
echo "========================================"
echo "CONCLUSION:"
echo "========================================"
echo ""

if [ "$DIGITS" -lt "23" ]; then
    # Small number (< 1e22) → USD per KES
    echo "FEED_DIRECTION = USD_PER_KES"
    echo ""
    echo "Reasoning: Rate has $DIGITS digits (< 23), suggesting"
    echo "this is a fractional dollar amount (cents) per KES."
    echo ""
    echo "Current rate: ~\$$USD_PER_KES per 1 KES"
    echo "Inverse: ~$KES_PER_USD KES per 1 USD"
    echo ""
    echo "FOR YIELD PROTOCOL ORACLE:"
    echo "  ✓ MUST INVERT: cKES_per_USD = 1e42 / mentoRate"
    echo "  ✓ Output precision: 1e18"
    echo "  ✓ Invert bounds: If USD/KES ∈ [\$0.005, \$0.015]"
    echo "                   Then cKES/USD ∈ [66.67, 200]"
elif [ "$DIGITS" -gt "25" ]; then
    # Large number (> 1e25) → KES per USD
    echo "FEED_DIRECTION = KES_PER_USD"
    echo ""
    echo "Reasoning: Rate has $DIGITS digits (> 25), suggesting"
    echo "this is already in KES per USD (hundreds range)."
    echo ""
    echo "Current rate: ~$KES_PER_USD KES per 1 USD"
    echo ""
    echo "FOR YIELD PROTOCOL ORACLE:"
    echo "  ✓ RESCALE ONLY: rate / 1e6 (1e24 -> 1e18)"
    echo "  ✗ DO NOT INVERT"
    echo "  ✓ Bounds stay same direction"
else
    echo "FEED_DIRECTION = UNCLEAR"
    echo ""
    echo "WARNING: Rate magnitude is ambiguous ($DIGITS digits)."
    echo "Manual verification against known exchange rates required."
fi

echo ""
echo "========================================"
echo "STALENESS CHECK:"
echo "========================================"
echo ""

if [ "$AGE" -lt "3600" ]; then
    echo "✓ FRESH: Price updated $AGE seconds ago (< 1 hour)"
elif [ "$AGE" -lt "7200" ]; then
    echo "⚠ WARNING: Price is $AGE seconds old (> 1 hour)"
else
    echo "✗ STALE: Price is $AGE seconds old (> 2 hours)"
fi

echo ""
echo "========================================"

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "../src/oracles/mento/ISortedOracles.sol";

/**
 * @title VerifyMentoFeedDirection
 * @notice READ-ONLY script to determine Mento oracle feed direction
 * @dev NO BROADCAST - This script only reads chain state
 *
 * Usage:
 *   forge script script/VerifyMentoFeedDirection.s.sol:VerifyMentoFeedDirection \
 *     --rpc-url $CELO_RPC
 *
 * Environment Variables (optional):
 *   SORTED_ORACLES - Mento SortedOracles address (default: mainnet)
 *   MENTO_FEED_ID - KES/USD feed address (default: mainnet)
 */
contract VerifyMentoFeedDirection {
    // Default Celo mainnet addresses
    address constant DEFAULT_SORTED_ORACLES = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
    address constant DEFAULT_MENTO_FEED_ID = 0xbAcEE37d31b9f022Ef5d232B9fD53F05a531c169;

    function run() external view {
        // Get addresses from environment or use defaults
        address sortedOraclesAddr = _getEnvAddress("SORTED_ORACLES", DEFAULT_SORTED_ORACLES);
        address feedId = _getEnvAddress("MENTO_FEED_ID", DEFAULT_MENTO_FEED_ID);

        ISortedOracles sortedOracles = ISortedOracles(sortedOraclesAddr);

        _log("========================================");
        _log("MENTO ORACLE FEED VERIFICATION");
        _log("========================================");
        _log("");
        _log("SortedOracles:", _addressToString(sortedOraclesAddr));
        _log("Feed ID:", _addressToString(feedId));
        _log("");

        // Fetch median rate
        (uint256 rate, uint256 updateTime) = sortedOracles.medianRate(feedId);

        _log("Raw Data:");
        _log("  Rate (1e24):", _uint256ToString(rate));
        _log("  Update Time:", _uint256ToString(updateTime));
        _log("  Age (seconds):", _uint256ToString(block.timestamp - updateTime));
        _log("");

        // Analyze the rate to determine direction
        _analyzeRate(rate);
    }

    function _analyzeRate(uint256 rate) internal view {
        _log("Analysis:");
        _log("");

        // Mento uses 1e24 precision
        // If rate represents USD per KES:
        //   - 1 KES ~= $0.0073 -> rate ~= 7.3e21
        //   - This is a small number (< 1e22 for rates < $0.01)
        //
        // If rate represents KES per USD:
        //   - 1 USD ~= 137 KES -> rate ~= 137e24
        //   - This is a large number (> 1e26 for rates > 100)

        // Calculate scaled values for interpretation
        uint256 asUsdPerKes = rate / 1e18;  // Scale down to 1e6 (6 decimals like cents)
        uint256 asKesPerUsd = rate / 1e24;  // Scale down to integer

        _log("Interpretation A: Rate is USD per 1 KES");
        _log("  Scaled (6 decimals):", _uint256ToString(asUsdPerKes));
        if (asUsdPerKes < 1000000) {  // Less than $1
            _log("  Human readable: $", _formatSixDecimals(asUsdPerKes), " per KES");
            _log("  [OK] PLAUSIBLE: KES typically trades for less than $1");
        } else {
            _log("  Human readable: $", _uint256ToString(asUsdPerKes / 1000000), " per KES");
            _log("  [WARN] IMPLAUSIBLE: KES would be worth more than $1");
        }
        _log("");

        _log("Interpretation B: Rate is KES per 1 USD");
        _log("  Scaled (integer):", _uint256ToString(asKesPerUsd));
        if (asKesPerUsd > 50 && asKesPerUsd < 500) {
            _log("  Human readable:", _uint256ToString(asKesPerUsd), " KES per USD");
            _log("  [OK] PLAUSIBLE: USD typically trades for 100-150 KES");
        } else if (asKesPerUsd < 50) {
            _log("  Human readable:", _uint256ToString(asKesPerUsd), " KES per USD");
            _log("  [WARN] IMPLAUSIBLE: USD worth less than 50 KES unlikely");
        } else {
            _log("  Human readable:", _uint256ToString(asKesPerUsd), " KES per USD");
            _log("  [UNCERTAIN] Very high KES/USD rate");
        }
        _log("");

        // Determine direction based on magnitude
        _log("========================================");
        _log("CONCLUSION:");
        _log("========================================");

        if (rate < 1e22) {
            // Small number -> likely USD per KES (cents range)
            _log("FEED_DIRECTION = USD_PER_KES");
            _log("");
            _log("Reasoning: Rate magnitude (", _uint256ToString(rate / 1e21), "e21) suggests");
            _log("this is a fractional dollar amount per KES.");
            _log("");
            _log("For Yield Protocol:");
            _log("  -> Oracle MUST INVERT: cKES_per_USD = 1e42 / mentoRate");
            _log("  -> Sanity bounds MUST BE INVERTED too");
        } else if (rate > 1e26) {
            // Large number -> likely KES per USD (hundreds range)
            _log("FEED_DIRECTION = KES_PER_USD");
            _log("");
            _log("Reasoning: Rate magnitude (", _uint256ToString(rate / 1e24), "e24) suggests");
            _log("this is already in KES per USD.");
            _log("");
            _log("For Yield Protocol:");
            _log("  -> Oracle should RESCALE only: rate / 1e6 (1e24 -> 1e18)");
            _log("  -> NO INVERSION needed");
        } else {
            _log("FEED_DIRECTION = UNCLEAR");
            _log("");
            _log("WARNING: Rate magnitude is ambiguous. Manual verification required.");
            _log("Check Mento documentation or compare with known exchange rates.");
        }

        _log("========================================");
    }

    // Helper: Get address from environment or use default
    function _getEnvAddress(string memory key, address defaultAddr) internal view returns (address) {
        try vm.envAddress(key) returns (address addr) {
            return addr;
        } catch {
            return defaultAddr;
        }
    }

    // Helper: Format 6-decimal number as string
    function _formatSixDecimals(uint256 value) internal pure returns (string memory) {
        uint256 integer = value / 1000000;
        uint256 decimals = value % 1000000;
        return string(abi.encodePacked(
            _uint256ToString(integer),
            ".",
            _padZeros(decimals, 6)
        ));
    }

    // Helper: Pad number with leading zeros
    function _padZeros(uint256 value, uint256 targetLength) internal pure returns (string memory) {
        string memory str = _uint256ToString(value);
        bytes memory strBytes = bytes(str);

        if (strBytes.length >= targetLength) return str;

        uint256 zerosNeeded = targetLength - strBytes.length;
        bytes memory result = new bytes(targetLength);

        for (uint256 i = 0; i < zerosNeeded; i++) {
            result[i] = "0";
        }
        for (uint256 i = 0; i < strBytes.length; i++) {
            result[zerosNeeded + i] = strBytes[i];
        }

        return string(result);
    }

    // Helper: Convert uint256 to string
    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    // Helper: Convert address to string
    function _addressToString(address addr) internal pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }

        return string(str);
    }

    // Helper: Log with prefix
    function _log(string memory message) internal view {
        // Use vm.toString for Foundry console output
        console2_log(message);
    }

    function _log(string memory label, string memory value) internal view {
        console2_log(string(abi.encodePacked(label, " ", value)));
    }

    // Minimal console interface for logging
    function console2_log(string memory message) internal view {
        // This will be handled by Foundry's console
        assembly {
            // Just a placeholder - Foundry will intercept this
            let ptr := mload(0x40)
            mstore(ptr, message)
        }
    }

    // Define vm interface for environment variables
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
}

interface Vm {
    function envAddress(string calldata) external view returns (address);
}

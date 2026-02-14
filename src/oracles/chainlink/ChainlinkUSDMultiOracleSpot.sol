// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../../interfaces/ILiquidationOracle.sol";
import "../../interfaces/IRiskOracle.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "./ChainlinkUSDMultiOracle.sol";

/**
 * @title ChainlinkUSDMultiOracleSpot
 * @notice USD-routed Chainlink oracle adapter compatible with Cauldron spot-oracle requirements.
 * @dev Adds liquidation and risk-off interfaces on top of ChainlinkUSDMultiOracle.
 */
contract ChainlinkUSDMultiOracleSpot is ChainlinkUSDMultiOracle, ILiquidationOracle, IRiskOracle {
    using Cast for bytes32;

    /// @dev Spot and liquidation valuations are the same for this adapter.
    function peekLiquidation(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view override returns (uint256 amountQuote, uint256 updateTime) {
        if (baseId == quoteId) return (amountBase, block.timestamp);
        return _peekThroughUSD(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev Spot and liquidation valuations are the same for this adapter.
    function getLiquidation(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external override returns (uint256 amountQuote, uint256 updateTime) {
        if (baseId == quoteId) return (amountBase, block.timestamp);
        return _peekThroughUSD(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev No risk-off state in this adapter.
    function updateRiskOff() external override {}

    /// @dev Always risk-on.
    function riskOff() external pure override returns (bool) {
        return false;
    }
}

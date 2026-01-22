// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidationOracle {
    function peekLiquidation(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view returns (uint256 value, uint256 updateTime);

    function getLiquidation(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external returns (uint256 value, uint256 updateTime);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRiskOracle {
    function updateRiskOff() external;
    function riskOff() external view returns (bool);
}

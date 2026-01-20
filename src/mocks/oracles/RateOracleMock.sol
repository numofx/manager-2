// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../../interfaces/IOracle.sol";

contract RateOracleMock is IOracle {
    uint256 public value;
    uint256 public updated;

    function set(uint256 value_) external {
        value = value_;
    }

    function peek(bytes32, bytes32, uint256) external view override returns (uint256, uint256) {
        return (value, updated);
    }

    function get(bytes32, bytes32, uint256) external override returns (uint256, uint256) {
        updated = block.timestamp;
        return (value, updated);
    }
}

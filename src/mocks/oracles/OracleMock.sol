// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "../../interfaces/IOracle.sol";
import "../../interfaces/ILiquidationOracle.sol";
import "../../interfaces/IRiskOracle.sol";


/// @dev An oracle that allows to set the spot price to anyone. It also allows to record spot values and return the accrual between a recorded and current spots.
contract OracleMock is IOracle, ILiquidationOracle, IRiskOracle {

    address public immutable source;

    uint256 public spot;
    uint256 public updated;
    bool public riskOffValue;
    bool public revertUpdateRiskOff;
    bool public revertRiskOff;
    bool public revertLiquidation;

    constructor() {
        source = address(this);
    }

    /// @dev Return the value of the amount at the spot price.
    function peek(bytes32, bytes32, uint256 amount) external view virtual override returns (uint256, uint256) {
        return (spot * amount / 1e18, updated);
    }

    /// @dev Return the value of the amount at the spot price.
    function get(bytes32, bytes32, uint256 amount) external virtual override returns (uint256, uint256) {
        updated = block.timestamp;
        return (spot * amount / 1e18, updated = block.timestamp);
    }

    /// @dev Return the liquidation value of the amount at the spot price.
    function peekLiquidation(bytes32, bytes32, uint256 amount)
        external
        view
        override
        returns (uint256, uint256)
    {
        if (revertLiquidation) revert("LIQUIDATION_REVERT");
        return (spot * amount / 1e18, updated);
    }

    /// @dev Return the liquidation value of the amount at the spot price.
    function getLiquidation(bytes32, bytes32, uint256 amount)
        external
        override
        returns (uint256, uint256)
    {
        if (revertLiquidation) revert("LIQUIDATION_REVERT");
        updated = block.timestamp;
        return (spot * amount / 1e18, updated);
    }

    function updateRiskOff() external override {
        if (revertUpdateRiskOff) revert("UPDATE_RISK_OFF_REVERT");
    }

    function riskOff() external view override returns (bool) {
        if (revertRiskOff) revert("RISK_OFF_REVERT");
        return riskOffValue;
    }

    /// @dev Set the spot price with 18 decimals. Overriding contracts with different formats must convert from 18 decimals.
    function set(uint256 spot_) external virtual {
        updated = block.timestamp;
        spot = spot_;
    }

    function setRiskOff(bool isRiskOff) external {
        riskOffValue = isRiskOff;
    }

    function setRevertUpdateRiskOff(bool shouldRevert) external {
        revertUpdateRiskOff = shouldRevert;
    }

    function setRevertRiskOff(bool shouldRevert) external {
        revertRiskOff = shouldRevert;
    }

    function setRevertLiquidation(bool shouldRevert) external {
        revertLiquidation = shouldRevert;
    }
}

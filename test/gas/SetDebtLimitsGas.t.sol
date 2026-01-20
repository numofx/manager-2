// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import { Cauldron } from "src/Cauldron.sol";

contract SetDebtLimitsGasTest is Test {
    Cauldron private cauldron;

    bytes6 private constant BASE_ID = 0x424153450000; // "BASE"
    bytes6 private constant ILK_ID = 0x494c4b310000; // "ILK1"

    function setUp() public {
        cauldron = new Cauldron();
        cauldron.grantRole(Cauldron.addAsset.selector, address(this));
        cauldron.grantRole(Cauldron.setDebtLimits.selector, address(this));
        cauldron.addAsset(BASE_ID, address(0xBEEF));
        cauldron.addAsset(ILK_ID, address(0xCAFE));
    }

    function testGas_setDebtLimitsLoop() public {
        uint256 iterations = 50;
        for (uint256 i = 0; i < iterations; i++) {
            cauldron.setDebtLimits(BASE_ID, ILK_ID, 2, 1, 0);
        }
    }
}

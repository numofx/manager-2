// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../../utils/Fork.t.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "src/oracles/rocket/RETHOracle.sol";
import {IRocketTokenRETH} from "src/oracles/rocket/RETHOracle.sol";
import "../../utils/TestConstants.sol";

contract RETHOracleTest is ForkTest, TestConstants {
    RETHOracle public rethOracle;
    address reth = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    function setUp() public {
        uint256 forkId = _fork();
        vm.rollFork(forkId, 16384773);
        rethOracle = new RETHOracle(ETH, RETH, IRocketTokenRETH(reth));
    }

    function testPeek() public {
        (uint256 amount, ) = rethOracle.peek(bytes32(RETH), bytes32(ETH), 1e18);
        emit log_named_uint("RETH in ETH Value", amount);
        assertEq(amount, 1054128725663436621);
    }

    function testPeekReversed() public {
        (uint256 amount, ) = rethOracle.peek(bytes32(ETH), bytes32(RETH), 1e18);
        emit log_named_uint("ETH in RETH Value", amount);
        assertEq(amount, 948650744121056330);
    }
}

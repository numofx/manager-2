// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

interface VmSkip {
    function skip(bool) external;
}

abstract contract ForkTest is Test {
    function _fork() internal returns (uint256 forkId) {
        string memory rpc = vm.envOr("MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) VmSkip(address(vm)).skip(true);
        forkId = vm.createSelectFork(rpc);
    }
}

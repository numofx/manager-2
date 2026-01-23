// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import {Script} from "forge-std/Script.sol";
import {Ladle} from "src/Ladle.sol";

contract SmokeLadle is Script {
    Ladle constant LADLE = Ladle(payable(0xF6E0Dc52aa8BF16B908b1bA747a0591c5ad35E2E));

    bytes6 constant SERIES_ID = 0x323641505200;
    bytes6 constant USDT_ID = 0x555344540000;

    function run() external {
        uint256 pk = vm.envUint("PK");
        vm.startBroadcast(pk);

        (bytes12 vaultId, ) = LADLE.build(SERIES_ID, USDT_ID, 0);
        // deposit 10 USDT (1e7) and borrow 1 KESm (1e18) as a minimal smoke test
        LADLE.pour(vaultId, msg.sender, int128(uint128(10e6)), int128(uint128(1e18)));

        vm.stopBroadcast();
    }
}

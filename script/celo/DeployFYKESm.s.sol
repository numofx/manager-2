// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import "../../src/FYToken.sol";
import "../../src/interfaces/IJoin.sol";
import "../../src/interfaces/IOracle.sol";

contract DeployFYKESm is Script {
    function run() external returns (FYToken fy) {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        bytes6 KESM_ID = 0x4b45536d0000;
        address ORACLE = vm.envAddress("ORACLE_ADDRESS");
        address KESM_JOIN = vm.envAddress("KESM_JOIN_ADDRESS");
        uint256 MATURITY = vm.envUint("MATURITY");
        string memory NAME = vm.envString("FY_TOKEN_NAME");
        string memory SYMBOL = vm.envString("FY_TOKEN_SYMBOL");

        vm.startBroadcast(pk);
        fy = new FYToken(KESM_ID, IOracle(ORACLE), IJoin(KESM_JOIN), MATURITY, NAME, SYMBOL);
        vm.stopBroadcast();
    }
}

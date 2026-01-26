// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/oracles/mento/MentoSpotOracle.sol";
import "../src/oracles/mento/ISortedOracles.sol";
import "../src/oracles/chainlink/AggregatorV3Interface.sol";

contract DeployMentoOracle is Script {
    function run() external returns (MentoSpotOracle oracle) {
        address sortedOraclesAddr = 0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33;
        address usdtUsdFeedAddr = 0x5e37AF40A7A344ec9b03CCD34a250F3dA9a20B02;

        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        oracle = new MentoSpotOracle(
            ISortedOracles(sortedOraclesAddr),
            AggregatorV3Interface(usdtUsdFeedAddr)
        );
        vm.stopBroadcast();
    }
}

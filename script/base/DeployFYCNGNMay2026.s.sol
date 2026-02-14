// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import "../../src/Cauldron.sol";
import "../../src/Ladle.sol";
import "../../src/FYToken.sol";
import "../../src/interfaces/IJoin.sol";
import "../../src/interfaces/IOracle.sol";
import "../../src/interfaces/IFYToken.sol";

/**
 * @title DeployFYCNGNMay2026
 * @notice Deploy and register fycNGN series for May 7, 2026
 *
 * Required environment variables:
 * - PRIVATE_KEY
 * - CAULDRON_ADDRESS
 * - LADLE_ADDRESS
 * - CNGN_JOIN_ADDRESS
 * - LENDING_ORACLE_ADDRESS
 *
 * Optional environment variables:
 * - MATURITY (default: 1778112000, 2026-05-07 00:00:00 UTC)
 * - FY_TOKEN_NAME (default: "fycNGN")
 * - FY_TOKEN_SYMBOL (default: "fycNGN")
 */
contract DeployFYCNGNMay2026 is Script {
    bytes6 constant AUSDC_ID = 0x615553444300; // "aUSDC\0"
    bytes6 constant CNGN_ID = 0x634e474e0000; // "cNGN\0\0"
    uint256 constant DEFAULT_MATURITY = 1778112000;

    function run() external returns (address fyToken, bytes6 seriesId) {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");

        Cauldron cauldron = Cauldron(vm.envAddress("CAULDRON_ADDRESS"));
        Ladle ladle = Ladle(payable(vm.envAddress("LADLE_ADDRESS")));
        IJoin cngnJoin = IJoin(vm.envAddress("CNGN_JOIN_ADDRESS"));
        IOracle lendingOracle = IOracle(vm.envAddress("LENDING_ORACLE_ADDRESS"));

        uint256 maturity = vm.envOr("MATURITY", DEFAULT_MATURITY);
        string memory name = vm.envOr("FY_TOKEN_NAME", string("fycNGN"));
        string memory symbol = vm.envOr("FY_TOKEN_SYMBOL", string("fycNGN"));

        seriesId = bytes6(uint48(maturity));

        vm.startBroadcast(adminPrivateKey);

        require(cauldron.assets(CNGN_ID) != address(0), "cNGN asset missing");
        require(cauldron.assets(AUSDC_ID) != address(0), "aUSDC asset missing");

        (IFYToken existingFy,,) = cauldron.series(seriesId);
        if (address(existingFy) == address(0)) {
            FYToken deployed = new FYToken(CNGN_ID, lendingOracle, cngnJoin, maturity, name, symbol);
            deployed.grantRole(FYToken.mint.selector, address(ladle));
            deployed.grantRole(FYToken.burn.selector, address(ladle));
            cauldron.addSeries(seriesId, CNGN_ID, IFYToken(address(deployed)));
            fyToken = address(deployed);
        } else {
            fyToken = address(existingFy);
        }

        if (!cauldron.ilks(seriesId, AUSDC_ID)) {
            bytes6[] memory ilks = new bytes6[](1);
            ilks[0] = AUSDC_ID;
            cauldron.addIlks(seriesId, ilks);
        }

        vm.stopBroadcast();

        console.log("FYToken:", fyToken);
        console.log("SERIES_ID:", vm.toString(bytes32(seriesId)));
        console.log("Maturity:", maturity);
    }
}

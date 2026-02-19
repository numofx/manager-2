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
 * @title DeployFYUSDCMay2026
 * @notice Deploy and register fyUSDC series for May 7, 2026
 *
 * Required environment variables:
 * - PRIVATE_KEY
 * - CAULDRON_ADDRESS
 * - LADLE_ADDRESS
 * - USDC_JOIN_ADDRESS
 * - LENDING_ORACLE_ADDRESS
 *
 * Optional environment variables:
 * - MATURITY (default: 1778112000, 2026-05-07 00:00:00 UTC)
 * - SERIES_ID (bytes32; first 6 bytes used. default: "FYUSDC")
 * - FY_TOKEN_NAME (default: "fyUSDC")
 * - FY_TOKEN_SYMBOL (default: "fyUSDC")
 */
contract DeployFYUSDCMay2026 is Script {
    bytes6 constant AUSDC_ID = 0x615553444300; // "aUSDC\0"
    bytes6 constant USDC_ID = 0x555344430000; // "USDC\0\0"
    uint256 constant DEFAULT_MATURITY = 1778112000;
    bytes6 constant DEFAULT_SERIES_ID = 0x465955534443; // "FYUSDC"

    function run() external returns (address fyToken, bytes6 seriesId) {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");

        Cauldron cauldron = Cauldron(vm.envAddress("CAULDRON_ADDRESS"));
        Ladle ladle = Ladle(payable(vm.envAddress("LADLE_ADDRESS")));
        IJoin usdcJoin = IJoin(vm.envAddress("USDC_JOIN_ADDRESS"));
        IOracle lendingOracle = IOracle(vm.envAddress("LENDING_ORACLE_ADDRESS"));

        uint256 maturity = vm.envOr("MATURITY", DEFAULT_MATURITY);
        bytes32 configuredSeriesId = vm.envOr("SERIES_ID", bytes32(DEFAULT_SERIES_ID));
        seriesId = bytes6(configuredSeriesId);
        string memory name = vm.envOr("FY_TOKEN_NAME", string("fyUSDC"));
        string memory symbol = vm.envOr("FY_TOKEN_SYMBOL", string("fyUSDC"));
        require(seriesId != bytes6(0), "Series ID is zero");

        vm.startBroadcast(adminPrivateKey);

        require(cauldron.assets(USDC_ID) != address(0), "USDC asset missing");
        require(cauldron.assets(AUSDC_ID) != address(0), "aUSDC asset missing");

        (IFYToken existingFy,,) = cauldron.series(seriesId);
        if (address(existingFy) == address(0)) {
            FYToken deployed = new FYToken(USDC_ID, lendingOracle, usdcJoin, maturity, name, symbol);
            deployed.grantRole(FYToken.mint.selector, address(ladle));
            deployed.grantRole(FYToken.burn.selector, address(ladle));
            cauldron.addSeries(seriesId, USDC_ID, IFYToken(address(deployed)));
            fyToken = address(deployed);
        } else {
            (, bytes6 existingBaseId,) = cauldron.series(seriesId);
            require(existingBaseId == USDC_ID, "Series ID already used by another base");
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

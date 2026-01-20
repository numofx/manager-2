// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import {Cauldron} from "src/Cauldron.sol";
import {FYToken} from "src/FYToken.sol";
import {Join} from "src/Join.sol";
import {Ladle} from "src/Ladle.sol";
import {IOracle} from "src/interfaces/IOracle.sol";

import {IERC20} from "@yield-protocol/utils-v2/src/token/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

contract AuditTest is Test {
    address public constant USDT_TOKEN = 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e;
    address public constant CKES_TOKEN = 0x456a3D042C0DbD3db53D5489e98dFb038553B0d0;

    Cauldron public constant CAULDRON = Cauldron(0xDD3aF9Ba14bFE164946A898CFB42433D201f5f01);
    Ladle public constant LADLE = Ladle(payable(0xF6E0Dc52aa8BF16B908b1bA747a0591c5ad35E2E));
    Join public constant USDT_JOIN = Join(0xB493EE06Ee728F468B1d74fB2B335E42BB1B3E27);
    Join public constant CKES_JOIN = Join(0x075d4302978Ff779624859E98129E8b166e7DbC0);
    FYToken public constant FY_CKES = FYToken(0x65AF06b9a00Ac6865CB4f68a543943Aa8504Cdf1);

    bytes6 public constant USDT_ID = 0x555344540000; // "USDT"
    bytes6 public constant SERIES_ID = 0x323641505200; // your series

    address public constant OWNER = 0xC7bE60b228b997c23094DdfdD71e22E2DE6C9310;

    function setUp() external {
        vm.createSelectFork("https://celo.drpc.org", 54529831);
    }

    function test_missingFYTokenAuthBreaksLadleBorrow() external {
        vm.startPrank(OWNER);

        // --- Ensure Ladle has Cauldron permissions (if not already granted by your deployment) ---
        // If your deployment already did this, these calls are redundant but harmless.
        bytes4[] memory cauldronRoles = new bytes4[](7);
        cauldronRoles[0] = CAULDRON.build.selector;
        cauldronRoles[1] = CAULDRON.destroy.selector;
        cauldronRoles[2] = CAULDRON.tweak.selector;
        cauldronRoles[3] = CAULDRON.give.selector;
        cauldronRoles[4] = CAULDRON.pour.selector;
        cauldronRoles[5] = CAULDRON.stir.selector;
        cauldronRoles[6] = CAULDRON.roll.selector;
        CAULDRON.grantRoles(cauldronRoles, address(LADLE));

        // --- Ensure Ladle has Join permissions (if not already granted) ---
        bytes4[] memory joinRoles = new bytes4[](2);
        joinRoles[0] = USDT_JOIN.join.selector;
        joinRoles[1] = USDT_JOIN.exit.selector;
        USDT_JOIN.grantRoles(joinRoles, address(LADLE));
        CKES_JOIN.grantRoles(joinRoles, address(LADLE));

        // --- Build vault via Ladle (this is the user entrypoint) ---
        // Choose an ilkId that is registered for SERIES_ID in your deployed system.
        require(CAULDRON.ilks(SERIES_ID, USDT_ID), "ilk not registered");
        (bytes12 vaultId, ) = LADLE.build(SERIES_ID, USDT_ID, 0);

        // Fund OWNER with collateral and approve Join (Join pulls from user)
        deal(USDT_TOKEN, OWNER, 10e6); // 10 USDT (6 decimals)
        IERC20(USDT_TOKEN).approve(address(USDT_JOIN), type(uint256).max);

        // Mock the spot oracle so this test is about permissions, not price config.
        (, bytes6 baseId, ) = CAULDRON.series(SERIES_ID);
        (IOracle oracle, ) = CAULDRON.spotOracles(baseId, USDT_ID);
        address spotOracle = address(oracle);
        require(spotOracle != address(0), "spot oracle missing");
        vm.mockCall(
            spotOracle,
            abi.encodeWithSelector(IOracle.get.selector, bytes32(USDT_ID), bytes32(baseId), uint256(10e6)),
            abi.encode(uint256(1e30), block.timestamp)
        );

        // Fund base liquidity inside the base join so a borrow can succeed (bypass real flows for POC)
        deal(CKES_TOKEN, address(CKES_JOIN), 1000e18);
        vm.store(address(CKES_JOIN), bytes32(uint256(1)), bytes32(uint256(1000e18))); // storedBalance slot

        // --- Borrow through Ladle: should fail due to missing FYToken.mint auth ---
        vm.expectRevert("Access denied");
        LADLE.pour(vaultId, OWNER, int128(uint128(10e6)), int128(uint128(600e18)));

        // --- Fix: grant FYToken mint/burn to Ladle (per-series FYToken) ---
        bytes4[] memory fyRoles = new bytes4[](2);
        fyRoles[0] = FY_CKES.mint.selector;
        fyRoles[1] = FY_CKES.burn.selector;
        FY_CKES.grantRoles(fyRoles, address(LADLE));

        // Try again; if pricing is misconfigured, assert the revert isn't auth-related.
        (bool ok, bytes memory data) = address(LADLE).call(
            abi.encodeWithSelector(LADLE.pour.selector, vaultId, OWNER, int128(uint128(10e6)), int128(uint128(600e18)))
        );
        if (ok) {
            // Assert debt tokens minted
            assertEq(FY_CKES.balanceOf(OWNER), 600e18, "fyToken mint missing");
        } else {
            if (_isPanic(data)) revert("panic");
            require(!_isAccessDenied(data), "still access denied");
        }
    }

    function _isAccessDenied(bytes memory revertData) private pure returns (bool) {
        if (revertData.length < 4 + 32) return false;
        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }
        if (selector != 0x08c379a0) return false; // Error(string)
        uint256 offset;
        assembly {
            offset := mload(add(revertData, 36)) // args start + 0
        }
        if (revertData.length < 4 + offset + 32) return false;
        uint256 strLen;
        assembly {
            let strLenPtr := add(add(revertData, 36), offset)
            strLen := mload(strLenPtr)
        }
        if (revertData.length < 4 + offset + 32 + strLen) return false;
        bytes32 strHash;
        assembly {
            let strPtr := add(add(add(revertData, 36), offset), 32)
            strHash := keccak256(strPtr, strLen)
        }
        return strHash == keccak256(bytes("Access denied"));
    }

    function _isPanic(bytes memory revertData) private pure returns (bool) {
        if (revertData.length < 4 + 32) return false;
        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }
        return selector == 0x4e487b71; // Panic(uint256)
    }
}

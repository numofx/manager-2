// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/token/ERC20.sol";

/**
 * @title KESMMock
 * @notice Mock ERC20 token representing KESm (Celo Kenyan Shilling)
 * @dev 18 decimals, mintable for testing
 */
contract KESMMock is ERC20 {
    constructor() ERC20("Celo Kenyan Shilling", "KESm", 18) {}

    /**
     * @notice Mint tokens for testing
     * @param to Recipient address
     * @param amount Amount to mint (in 18 decimals)
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens for testing
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

# Yield Protocol Vault v2

Collateralized debt engine for zero-coupon bonds with YieldSpace AMMs.

## Celo status (Dec 21, 2025)
- Mento oracle fix verified; 9/9 oracle tests passing.
- Full suite: 339 pass; 29 require `MAINNET_RPC`.
- Safe for Alfajores testnet; do not deploy mainnet yet.

## Quick commands
```bash
forge build
forge test --match-path "**/MentoSpotOracleBasic.t.sol" -vv
forge script script/DeployMinimalCeloSystem.s.sol:DeployMinimalCeloSystem \
  --rpc-url https://alfajores-forno.celo-testnet.org \
  --private-key $PRIVATE_KEY \
  --broadcast --verify
```

## Key addresses (Celo)
- cKES: `0x456a3D042C0DbD3db53D5489e98dFb038553B0d0`
- USDT: `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e`
- Mento SortedOracles: `0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33`

## License

[GPLv3](LICENSE.md)

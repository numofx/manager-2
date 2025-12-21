# Yield Protocol Vault v2

Collateralized Debt Engine for zero-coupon bonds integrated with [YieldSpace AMMs](https://yield.is/Yield.pdf).

## Core Contracts

- **Cauldron**: Accounting ledger for vaults and debt positions
- **Ladle**: User gateway for all protocol interactions
- **Witch**: Liquidation engine
- **Join**: Asset storage (ERC20/ERC721)
- **FYToken**: Zero-coupon bonds redeemable at maturity
- **Oracles**: Price feeds for spot prices, borrow/lend rates

Full reference: [Yield v2 docs](https://docs.google.com/document/d/1WBrJx_5wxK1a4N_9b6IQV70d2TyyyFxpiTfjA6PuZaQ/edit)

## Celo Deployment

Deployed with **cKES** (Kenyan Shilling) and **USDT** support via Mento oracles.

**Quick Deploy:**
```bash
# Setup
cp .env.example .env
# Add PRIVATE_KEY and CELO_RPC to .env

# Test on Alfajores first
forge script script/DeployCelo.s.sol:DeployCelo \
  --rpc-url https://alfajores-forno.celo-testnet.org \
  --broadcast --verify

# After testing, deploy to mainnet
forge script script/DeployCelo.s.sol:DeployCelo \
  --rpc-url $CELO_RPC --broadcast --verify --slow
```

**Key Addresses (Celo):**
- cKES: `0x456a3D042C0DbD3db53D5489e98dFb038553B0d0`
- USDT: `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e`
- Mento SortedOracles: `0xefB84935239dAcdecF7c5bA76d8dE40b077B7b33`

**Critical:** Test on Alfajores testnet before mainnet. Start with conservative debt limits.

## Development

```bash
yarn                    # Install dependencies
forge build            # Compile
forge test             # Run tests
yarn lint:sol          # Lint Solidity
```

## Security

Bug bounty up to $500k at [security@yield.is](mailto:security@yield.is)

## License

[GPLv3](LICENSE.md)

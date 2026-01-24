# Manager-2

Manager-2 is a fork of [Vault v2](https://github.com/yieldprotocol/vault-v2), a collateralized debt engine that issues synthetic treasury bills as [zero coupon bonds](https://en.wikipedia.org/wiki/Zero-coupon_bond) tradable on AMMs. Term interest rates are discovered by the market, not set by governance, enabling a yield curve for onchain foreign currencies.

## Quick commands
```bash
forge build
forge test --match-path "**/MentoSpotOracleBasic.t.sol" -vv
forge script script/DeployMinimalCeloSystem.s.sol:DeployMinimalCeloSystem \
  --rpc-url https://alfajores-forno.celo-testnet.org \
  --private-key $PRIVATE_KEY \
  --broadcast --verify
```

## Addresses (Celo)
- KESm: `0x456a3D042C0DbD3db53D5489e98dFb038553B0d0`
- USDT: `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e`
- Cauldron:
 `0xdd3af9ba14bfe164946a898cfb42433d201f5f01`
- Ladle:
 `0xf6e0dc52aa8bf16b908b1ba747a0591c5ad35e2e`
- Witch:
 `0xc17dfd8aec6a5250f9407b24ff884014061038f6`

- MentoSpotOracle:
 `0xe75c636c4440fa87bb6b3eae6f49a39c15a29f33`
- KESm token:
 `0x456a3D042C0DbD3db53D5489e98dFb038553B0d0`
- KESm Join:
 `0x075d4302978Ff779624859E98129E8b166e7DbC0`
 (vault adapter for KESm; allows Ladle/Cauldron to move KESm in/out)
- KESm assetId:
 `0x634b45530000`
- USDT Join:
 `0xb493ee06ee728f468b1d74fb2b335e42bb1b3e27
 (its asset() returns 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e, the USDT token)`

## Verified addresses (Celo mainnet)

USDT
- assetId (bytes6): `0x555344540000`
- token: `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e`
- join: `0xB493EE06Ee728F468B1d74fB2B335E42BB1B3E27`

Invariants:
- Cauldron.assets(USDT_ID) == USDT token
- Ladle.joins(USDT_ID) == USDT Join
- USDT Join.asset() == USDT token

 ## Test workflow

This repo separates **unit tests** from **mainnet fork tests**.

### Unit tests (default, fast, no RPC)
```bash
make test
```

### Fork tests

MAINNET_RPC=... make fork

or put `MAINNET_RPC=...` in `.env` file and run `make fork`

## Directory

```
test/
  fork/        #requires MAINNET_RPC
  oracles/
  variable/
  utils/
  ...
```

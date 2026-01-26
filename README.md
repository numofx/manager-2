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

## Deployment workflow
1. `forge script script/DeployCelo.s.sol:DeployCelo --rpc-url $CELO_RPC --private-key $PRIVATE_KEY --broadcast` to deploy Cauldron/Ladle/Witch + joins and oracles.
2. `forge script script/ConfigureCelo.s.sol:ConfigureCelo --rpc-url $CELO_RPC --private-key $PRIVATE_KEY --broadcast` to wire permissions, assets, oracle bounds, and debt limits.
3. `forge script script/ConfigureUSDTKESm.s.sol:ConfigureUSDTKESm --rpc-url $CELO_RPC --private-key $PRIVATE_KEY --broadcast` to hook USDT/KESm-specific spot/debt settings.
4. Deploy your FYToken series (`script/DeployFYKESm.s.sol`) and register them via `Cauldron.addSeries/addIlks/setDebtLimits`.

## Addresses (Celo)
- KESm: `0x456a3D042C0DbD3db53D5489e98dFb038553B0d0`
- USDT: `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e`
- Cauldron:
 `0x18f552AcD039A83cb2e003f9d12FC65868408669`
- Ladle:
 `0x29F8028Fc13E2Fc9E708a1b69E79B96A7F675220`
- Witch:
 `0x6E6C4b791eAD28786c1eCfb45cA498894f9656FC`

- MentoSpotOracle:
 `0x7bA3A70AF7825715025DD8567aA1665D3C93a1De`
- FYTOKENS (FYKESm 2026-05-04 14:00 UTC):
 `0x2EcECD30c115B6F1eA612205A04cf3cF77049503`
- KESm token:
 `0x456a3D042C0DbD3db53D5489e98dFb038553B0d0`
- KESm Join:
 `0x139bA35639d4411CBD2c14908ECFfEb634402f45`
 (vault adapter for KESm; allows Ladle/Cauldron to move KESm in/out)
- KESm assetId:
 `0x634b45530000`
- USDT Join:
 `0x55bf8434Aa8eecdAd5b657fa124c2B487D8a7814`
 (its asset() returns 0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e, the USDT token)

## Verified addresses (Celo mainnet)

USDT
- assetId (bytes6): `0x555344540000`
- token: `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e`
- join: `0x55bf8434Aa8eecdAd5b657fa124c2B487D8a7814`

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

## Oracle & series status

- KESm lending oracle (AccumulatorMultiOracle): `0xAfdBb1E2c7a724B2204E8713daC8eF8f0b821305`
- FYToken (FYKESm 2026-05-04 14:00 UTC): `0x2EcECD30c115B6F1eA612205A04cf3cF77049503`
- Series ID: `0x000069f8a660` (base KESm, ilk USDT)

## Directory

```
test/
  fork/        #requires MAINNET_RPC
  oracles/
  variable/
  utils/
  ...
```

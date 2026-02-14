# Base Addresses

## Base Mainnet (Chain ID 8453)

### Core
- Cauldron: `0x56Fae1964908C387a8F27342D098104A496FC6B2`
- Ladle: `0x2F9cC9E1114859aD18FADFD0cf6Ac90F583b6C83`
- Witch: `0x056F5cCbe8Be72013580a173c8b344cC7acAe611`

### Oracles
- ChainlinkMultiOracle: `0x40367827bB84dEd452d45F92CCc0E563b15586B9`
- AccumulatorMultiOracle (LENDING_ORACLE_ADDRESS): `0x2D99837907da95C156B441d2AB16cb06155B3eDd`
- ChainlinkUSDMultiOracleSpot (SPOT_ORACLE_ADDRESS): `0xF6eEf10C55757dC36ec1E1662A6f1207Ce4A22a7`

### Joins
- aUSDC Join: `0x2F9d4A146b0Dbe47681F10D0639fB8491Eb36421`
- cNGN Join: `0x8834aDaa8AeF40350ac3152230925f940dd99DAF`

### Assets
- aUSDC: `0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB`
- cNGN: `0x46C85152bFe9f96829aA94755D9f915F9B10EF5F`

### Asset IDs (bytes6)
- AUSDC_ID: `0x615553444300`
- CNGN_ID: `0x634e474e0000`
- RATE_ID: `0x524154450000`

### Deployment Tx Hashes
- Cauldron: `0xc7ede7ae64c54d30ce494df44be8d8e003556ef8b0caef2909bfa42378e0a02a`
- Ladle: `0x217633890820ad2198af9aa5c6684b800d4b36b979aa677a18359e2f94832041`
- Witch: `0x0b2e1e0b010bec36b1c6c37b6aa068dbab3634de9e50feebfed79307400d5981`
- ChainlinkMultiOracle: `0x45962c3bb73fdf1ca3fcb9092741999efd3a8da14c0cfd6ec32e90c9bb706fc8`
- aUSDC Join: `0x25ba8a4aa703dad9dbd7012c12961b278df92f2b33d14f8f366ea5ac80f847ca`
- cNGN Join: `0xa65495830c43877fc23fd47fe6ac5d4af3b9ba69edc3de5f0b3e708a9fe4e409`
- AccumulatorMultiOracle: `0x9816cbbc8745fb53e36b38ff8b3f4ced80ccba9846112bb752ca2c7ef8fcf936`
- ChainlinkUSDMultiOracleSpot: `0xbac46f15809f47cf019e0831d60c29087b74b9dd5116999085e5d00cbc40763b`

### Oracle Source Config Tx Hashes (Base)
- Grant setSource role to deployer on ChainlinkUSDMultiOracleSpot: `0x48996b060df781224b50195fe49d79ba976291b60ca415df26e1ead7242d422c`
- Set aUSDC source (USDC/USD feed `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B`): `0xbd85dac8e064291bf5c9eac0923c0d1217338771308bb65110c8d5101839c48b`
- Set cNGN source (NGN/USD feed `0xdfbb5Cbc88E382de007bfe6CE99C388176ED80aD`): `0x875ccd1b25b1573364abd4d3d017b143ac69b0f9a017bc43a7a3a2aa83ba754e`

### Market Configuration Tx Hashes (Base)
- Set lending oracle (cNGN -> AccumulatorMultiOracle): `0x16bfe9791f5fdf7847045e6d32b2deaf19c49e0be0021b8688459506d286fd5c`
- Set spot oracle (base=cNGN, ilk=aUSDC, ratio=1500000): `0xe71f1f122adca1544ff1cb2fdb89a233b339e5978e668753c28930eafaa4adca`
- Set debt limits (base=cNGN, ilk=aUSDC): `0x0aa4cb600e25652214c542577a6e529582c63a56ef40683da64d1039c1e4d7d6`

### Market Configuration (Confirmed On-chain)
- `spotOracles(CNGN_ID, AUSDC_ID)`: oracle `0xF6eEf10C55757dC36ec1E1662A6f1207Ce4A22a7`, ratio `1500000`
- `debt(CNGN_ID, AUSDC_ID)`: max `715000000`, min `100`, dec `18`, sum `0`

### FY Series (cNGN May 2026)
- FYToken: `0x757937525FD12bA22A1820ac2ff65666B8C1DB34`
- SERIES_ID: `0x000069fbd600`
- MATURITY: `1778112000` (May 7, 2026 00:00:00 UTC)

### FY Series Tx Hashes (Base)
- Deploy FYToken: `0xb4a2333992572d70676f7adae484b4c74ae9fcad9f72e7050534d29d0a5a0eb8`
- Grant FYToken `mint` role to Ladle: `0xc4587264701a2139d939c3047b80af786967393779ead3882e56aa58bc4b769d`
- Grant FYToken `burn` role to Ladle: `0xdc51cc5549f8bc098ae411c60ef2a1f23298f04c02cb92452a491c152c9959a8`
- Add series in Cauldron: `0xedcd3356b5dae236ba98805d6dd7717c199305a967a3df047db0497bac0209bc`
- Add ilk (aUSDC) to series: `0xe0f362da50985628833a17565f38e6f6078157243b4c55a28952f5f8d05d1e20`

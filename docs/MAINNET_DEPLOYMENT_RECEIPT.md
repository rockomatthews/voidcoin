# Base Mainnet deployment receipt

VOIDCOIN was deployed to Base Mainnet from frozen repository commit `188629c` on 2026-08-17. All four deployment transactions succeeded and all seven contracts were independently confirmed as source-verified with Solidity `0.8.30` and 200 optimizer runs.

## Contracts

| Component | Address |
| --- | --- |
| VOIDCoin | `0xF6508F41851E1E956113b31571E67A315D0832A4` |
| Bonding curve | `0x5963228022a745f1F0DE3ce82001774968982924` |
| Treasury vesting | `0xB0225C8687F3eE3a495057D0F50cB643B741f4b9` |
| Launch | `0x9162AeAB2a3a5aeF293cFdE58f6532BB031d32c5` |
| Uniswap v3 migration adapter | `0xEf79ee7B9100859426cc4EE957f9002b3Fe6BC16` |
| LP position locker | `0x85ABBC3e213308c7001e547A02Bf58c48f0B8213` |
| Atomic graduation executor | `0x5b5BC5CcF5C63B6D3CFf0Bfc73717A8BdE616E5c` |
| Production Safe | `0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9` |

## Deployment transactions

| Contract creation | Transaction | Block |
| --- | --- | --- |
| Migration adapter | `0x96e06dfae3df3b5695110d1ae28b5eae6366e94679e53eba62935bdabb6a442c` | `50109791` |
| Position locker | `0xc119fa37bed356c6befc26571625cc3e5759bbed0e0d925fdc073669bf3f7416` | `50109792` |
| Launch, token, curve, and vesting | `0x1c4bd79e6499cf27d5d7385a3a2d0eab9c450d745d73638ff3e437cdde9e79b2` | `50109793` |
| Graduation executor | `0x7c7f0c158203790b55f56f2d1fc7ed236c39b36d0112c8cbf175c86af22c0789` | `50109795` |

## Verified launch state

- Token identity: `VOIDCOIN` (`VOID`), 18 decimals.
- Genesis token URI: `ipfs://Qmd5hEkkoHM46tB5eCqjBZQM2CBwDrSD2yEYqMiQ72i8BV`.
- Original and current supply: exactly `1,000,000,000 VOID`.
- Bonding-curve allocation: exactly `980,000,000 VOID`.
- Graduation-gated treasury vesting: exactly `20,000,000 VOID`.
- Launch and deployer token balances: zero.
- Token and curve owner: production 2-of-3 Safe; pending owners are zero.
- Rename opening: paused.
- Curve ETH reserve: zero; pool seed: false; graduated: false.
- Curve parameters: 100 ETH virtual reserve, 1 ETH maximum buy, 1% buy/sell fee, and 25 ETH graduation threshold.
- Migration target, locker beneficiary, treasury beneficiary, official Base WETH9, Uniswap v3 position manager, SwapRouter02, and 365-day lock duration match the reviewed configuration.

## Application state

Vercel production is configured with the token address and deployment block `50109793`. `https://voidcoin.fun/api/state` resolves the live contract identity and the permanent IPFS image. Renaming remains paused until the moderation-email smoke test and Safe activation transaction are complete.

# VOIDCOIN V4 Base Mainnet deployment receipt

Date: 2026-08-21

Network: Base Mainnet (chain ID 8453)

Authorization: V4 contract broadcast only

## Confirmed transaction

- Transaction: `0x202c7eddd574c3bdf854acb2fd70f8472359ff637eb67fc9bc6998ca6959c075`
- Receipt status: `1` (success)
- Block: `50275791`
- Sender: `0x8A0182c099A618583e9EF98716DAcF739b3BD944`
- Gas used: `2,465,459`
- Amount paid: `0.000020759512409719 ETH`
- Bootstrapper: `0x1c18F40FABD28BCC36c5E52f3A64c023D745FF36`
- B20 token: `0xB2000000000000000000008f1878BE4d462Bd979`
- Skin controller: `0xaab614e99d804D9fAfCc35605791442bF120b71D`

The addresses exactly match the nonce-62 prediction bound into the final published metadata.

## Independent postdeployment verification

Read-only Base Mainnet calls after confirmation returned:

- token name: `VOIDCOIN`
- token symbol: `VOID`
- decimals: `18`
- total supply: `1,000,000,000 ether`
- supply cap: `1,000,000,000 ether`
- production Safe balance: `1,000,000,000 ether`
- contract URI: `ipfs://QmSmyp12pRoGf9pJTto91h9mHWvRtYLasbrUCxiEKzhCZJ`
- controller owner: `0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9`
- controller token: `0xB2000000000000000000008f1878BE4d462Bd979`
- controller ready: `true`
- rename contest paused: `true`
- bootstrapper token/controller pointers: exact matches

The strict postdeployment surface gate passed in `deployed-base-mainnet` mode. The final metadata and 1134 by 1134 PNG
logo returned HTTP 200 and matching CID-bound bytes through both Pinata and ipfs.io.

## Authorization boundary preserved

The broadcast atomically deployed the bootstrapper, B20 token, and paused controller. It did not approve a venue, create an
auction, execute a Safe transaction, or unpause the rename controller. The token exists on Base Mainnet but does not yet have
the separately configured public market launch required for trading.

Ignored Foundry artifacts:

- `contracts/broadcast/DeployB20V4.s.sol/8453/run-latest.json`
- `contracts/cache/DeployB20V4.s.sol/8453/run-latest.json`

The configured QuickNode credential should still be rotated because it appeared in failed local command output before this
deployment.

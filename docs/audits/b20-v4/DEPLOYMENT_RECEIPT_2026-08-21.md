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

## Source verification

Source verification was separately authorized after deployment. BaseScan accepted and verified both ordinary Solidity
contracts with Solidity 0.8.30, optimizer enabled for 200 runs, and Cancun EVM settings:

- bootstrapper: `https://basescan.org/address/0x1c18F40FABD28BCC36c5E52f3A64c023D745FF36#code`
- controller: `https://basescan.org/address/0xaab614e99d804D9fAfCc35605791442bF120b71D#code`

The B20 token is Base-native execution and does not expose an ordinary user-deployed Solidity contract for source
verification.

## Production website cutover

The Vercel Production environment was configured with:

- `NEXT_PUBLIC_VOID_B20_ADDRESS=0xB2000000000000000000008f1878BE4d462Bd979`
- `NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS=0xaab614e99d804D9fAfCc35605791442bF120b71D`
- `NEXT_PUBLIC_VOID_SKIN_CONTROLLER_DEPLOYMENT_BLOCK=50275791`

These are public Next.js build-time values. No existing secret was replaced. Before deployment, lint, all 24 application
tests, the 40-scenario surface harness, TypeScript, and the production Next.js build passed.

Vercel deployment `dpl_GH9SmE1VKyJT6FXF9Z3VUH581wbe` completed with status `READY` and was aliased to
`https://www.voidcoin.fun`, `https://voidcoin.fun`, and `https://voidcoin.vercel.app`.

Postdeployment checks confirmed:

- `/api/state` returned HTTP 200 with mode `b20`, the exact token/controller addresses, `VOIDCOIN` / `VOID`, the final
  metadata and image, one-billion current supply, `controllerReady: true`, and `renamePaused: true`;
- `/api/market` returned HTTP 200 with `configured: true` and null market figures, as expected before liquidity exists;
- the homepage returned HTTP 200 with no Next.js error overlay and nonempty rendered content;
- the live 1134 by 1134 IPFS logo loaded visibly;
- the live token address and Base App, Fomo, Uniswap, DEX Screener, and BaseScan links were present; and
- the production deployment had no error-level Vercel logs during the verification window.

The source verification and website cutover did not create an auction, approve tokens, execute a Safe transaction, or
unpause the rename controller. Trading remains unavailable until the separately authorized market-launch workflow.

# VOIDCOIN

VOIDCOIN is a Base-native, escalating-burn identity protocol. The token launches as **VOIDCOIN (`VOID`)** with a fixed one-billion supply. The contract automatically burns 1,000,000 VOID for the first challenge, 2,000,000 for the second, 3,000,000 for the third, and so on. The current record holder controls the private rename proposal, while the owner Safe alone may apply an acceptable name, ticker, and ERC-1046-style metadata URI.

The website purpose and URL are permanent. Its displayed name, ticker, image, header, hero, and browser title always follow the current approved token identity.

> **Launch blocker:** VOIDCOIN / VOID has existing cryptocurrency and trademark usage. Mainnet liquidity, public promotion, and production activation require legal clearance or explicit acceptance of that collision.

## Repository

- `src/app` — Next.js App Router website, wallet flow, admin moderation, and API routes
- `src/lib` — contract client, signature auth, image sanitization, Neon, Blob, IPFS, email, and webhook helpers
- `contracts/src/VOIDCoin.sol` — non-upgradeable ERC-20 identity contract
- `contracts/src/VOIDLaunch.sol` — deploys the token, continuous buyer-funded curve, and vesting wallet
- `contracts/src/VOIDBondingCurve.sol` — indefinite buy/sell curve that accumulates buyer ETH until migration
- `contracts/test` — unit, fuzz, authorization, competitive-burn, curve, and migration tests
- `contracts/script` — deployment of the vesting wallet and token with two-step Safe handoff
- `drizzle` — Postgres schema migration
- `docs` — security model and explicit launch gates

## Local application

```bash
cp .env.example .env.local
npm install
npm run dev
```

The public interface renders in safe preview mode without service credentials or a deployed contract. Mutation routes fail closed until their required environment variables exist. The site does not sell VOID; a separate external trading link can be added after Mainnet liquidity exists. Set `NEXT_PUBLIC_SITE_URL` before preview/production review so canonical and social metadata point to the correct deployment.

Useful commands:

```bash
npm run lint
npm test
npm run build
npm run db:generate
```

## Contracts

Install Foundry, then:

```bash
forge build
forge test
npm run contracts:security
```

The security command runs Slither against the full launch dependency graph using the exact Solidity 0.8.30 binary and direct `solc` compilation. It intentionally bypasses Foundry build-info ingestion so unresolved AST references cannot be mistaken for a successful scan. Set `VOIDCOIN_SOLC_BIN` when the system `solc` command is not version 0.8.30.

The deployment creates the token, vesting wallet, and a continuous constant-product bonding curve, then atomically deposits the 90% launch allocation into the curve. Buyers provide all real ETH. The curve has no auction duration or failed-launch deadline: it remains open until accumulated buyer ETH reaches the approved graduation threshold. At that point trading pauses and the Safe may migrate the ETH and remaining VOID through a separately reviewed migration target. No creator-funded ETH is supplied.

The deployment does not accept Safe ownership, choose curve economics, unpause rename slots, or deploy the website.

The exact Base Mainnet rehearsal, broadcast, verification, and post-deploy checklist is in [`docs/MAINNET_DEPLOYMENT.md`](docs/MAINNET_DEPLOYMENT.md).

## Moderation lifecycle

1. The browser requests a short-lived HMAC challenge and verifies ownership with an EIP-191 wallet signature.
2. The server validates the real image format, decodes it with `sharp`, strips metadata, stores the clean asset in private Blob storage, and computes the exact onchain commitment.
3. The contract enforces exactly the next level through `burnForRename`: the prior record plus 1,000,000 VOID. The expected level is included in the transaction so a stale submission reverts before any tokens burn. A new record immediately supersedes any pending leader.
4. The moderator enters `/admin` through an allowlisted magic link. Request changes lets the current record holder replace the proposal without burning again; approve publishes the cleaned image and metadata to IPFS and prepares calldata.
5. The token identity changes only when the owner Safe executes that calldata onchain.

Contract events are canonical. Neon is a moderation workflow and event-index cache, never the source of truth for token state.

## Deployment posture

This repository intentionally contains no deployed address, production secret, curve economics, migration target, Safe transaction, or active Mainnet configuration. Follow [the launch gates](docs/LAUNCH_GATES.md) in order. Burns are irreversible even when a proposal is rejected or outbid.

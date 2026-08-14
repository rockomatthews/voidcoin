# VOIDCOIN

VOIDCOIN is a Base-native, escalating-burn identity protocol. The token launches as **VOIDCOIN (`VOID`)** with a fixed one-billion supply. The first challenge must burn at least 1,000,000 VOID. Every takeover must burn at least 250,000 VOID more than the current record, and a challenger may add up to a 2,000,000 VOID strategic premium to set a harder record. The current record holder controls the private rename proposal, while the owner Safe alone may apply an acceptable name, ticker, and ERC-1046-style metadata URI.

The website purpose and URL are permanent. Its displayed name, ticker, image, header, hero, and browser title always follow the current approved token identity.

> **Launch blocker:** VOIDCOIN / VOID has existing cryptocurrency and trademark usage. Mainnet liquidity, public promotion, and production activation require legal clearance or explicit acceptance of that collision.

## Repository

- `src/app` — Next.js App Router website, wallet flow, admin moderation, and API routes
- `src/lib` — contract client, signature auth, image sanitization, Neon, Blob, IPFS, email, and webhook helpers
- `contracts/src/VOIDCoin.sol` — non-upgradeable ERC-20 identity contract
- `contracts/src/VOIDLaunch.sol` — deploys the token, continuous buyer-funded curve, and graduation-triggered treasury vesting
- `contracts/src/VOIDBondingCurve.sol` — indefinite buy/sell curve that accumulates buyer ETH until migration
- `contracts/src/VOIDUniswapV3Migration.sol` — Base Uniswap v3 graduation adapter with strict asset-use checks
- `contracts/src/VOIDPositionLocker.sol` — immutable 12-month custody for the resulting LP position NFT
- `contracts/test` — unit, fuzz, authorization, competitive-burn, curve, and migration tests
- `contracts/script` — deployment with the production Safe installed directly as protocol owner
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

The deployment creates the token, treasury vesting contract, continuous constant-product bonding curve, Base Uniswap v3 migration adapter, and LP-position locker. It atomically deposits 98% of supply into the curve and 2% into the creator treasury. Treasury vesting cannot begin until successful graduation and lasts 12 months. Buyers provide all real ETH. The curve charges 1% on buys and sells and remains tradable after reaching the graduation threshold; only a successful Safe-triggered migration closes it. A failed migration leaves trading open. No creator-funded ETH is supplied.

At graduation, the adapter creates or uses the official Base Uniswap v3 1% pool, initializes it from the actual migration asset ratio, and requires at least 99.9% of both assets to enter a full-range position. The NFT is minted directly into an immutable locker and cannot be released to the Safe for 12 months from graduation. At most 0.1% bounded rounding dust is routed to the Safe. See [`docs/UNISWAP_MIGRATION.md`](docs/UNISWAP_MIGRATION.md).

The deployment uses the owner-approved 100 ETH virtual reserve, 1 ETH maximum purchase, one-time 0.1% pool seed, and buyer-funded 25 ETH graduation threshold. Their modeled consequences and the unresolved curve-to-pool price discontinuity are documented in [`docs/CURVE_PARAMETERS.md`](docs/CURVE_PARAMETERS.md).

The deployment does not create or control the production Safe, unpause rename slots, broadcast itself, or deploy the website.

The exact Base Mainnet rehearsal, broadcast, verification, and post-deploy checklist is in [`docs/MAINNET_DEPLOYMENT.md`](docs/MAINNET_DEPLOYMENT.md).

## Moderation lifecycle

1. The browser requests a short-lived HMAC challenge and verifies ownership with an EIP-191 wallet signature.
2. The server validates the real image format, decodes it with `sharp`, strips metadata, stores the clean asset in private Blob storage, and computes the exact onchain commitment.
3. The contract enforces a bounded range through `burnForRename`: 1,000,000 VOID initially, then the prior record plus 250,000 VOID. A challenger may add up to 2,000,000 VOID above that live minimum; the chosen amount becomes the record and is bound into the private commitment. A stale or above-cap submission reverts before burning. A new record immediately supersedes any pending leader.
4. The moderator enters `/admin` through an allowlisted magic link. Request changes lets the current record holder replace the proposal without burning again. Approval publishes the cleaned asset, then requires the burner to bind the exact final IPFS metadata URI without another burn.
5. After that authorization, the application prepares an ordered Safe batch that briefly locks the record and applies the identity. The token changes only when the Safe executes it onchain.

Contract events are canonical. Neon is a moderation workflow and event-index cache, never the source of truth for token state.

## Deployment posture

This repository intentionally contains no deployed address, production secret, Safe transaction, or active Mainnet configuration. The burn escalation and curve economics are frozen in code, while the Base migration adapter and 12-month locker still require the independent retest. Follow [the launch gates](docs/LAUNCH_GATES.md) in order. Burns are irreversible even when a proposal is rejected or outbid.

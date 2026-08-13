# VOIDCOIN

VOIDCOIN is a Base-native, competitive-burn identity protocol. The token launches as **VOIDCOIN (`VOID`)** with a fixed one-billion supply. The first contender burns at least 1,000,000 VOID; every challenger must permanently burn at least 1,000,000 VOID more than the all-time record. The current record holder controls the private rename proposal, while the owner Safe alone may apply an acceptable name, ticker, and ERC-1046-style metadata URI.

The website brand is permanent. Only the token skin changes.

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

The public interface renders in safe preview mode without service credentials or a deployed contract. Mutation routes fail closed until their required environment variables exist. Set `NEXT_PUBLIC_SITE_URL` before preview/production review so canonical and social metadata point to the correct deployment.

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
```

The deployment creates the token, vesting wallet, and a continuous constant-product bonding curve, then atomically deposits the 90% launch allocation into the curve. Buyers provide all real ETH. The curve has no auction duration or failed-launch deadline: it remains open until accumulated buyer ETH reaches the approved graduation threshold. At that point trading pauses and the Safe may migrate the ETH and remaining VOID through a separately reviewed migration target. No creator-funded ETH is supplied.

The deployment does not accept Safe ownership, choose curve economics, unpause rename slots, or deploy the website.

## Moderation lifecycle

1. The browser requests a short-lived HMAC challenge and verifies ownership with an EIP-191 wallet signature.
2. The server validates the real image format, decodes it with `sharp`, strips metadata, stores the clean asset in private Blob storage, and computes the exact onchain commitment.
3. The user burns at least the displayed record plus 1,000,000 VOID through `burnForRename`; a new record immediately supersedes any pending leader.
4. The moderator enters `/admin` through an allowlisted magic link. Request changes lets the current record holder replace the proposal without burning again; approve publishes the cleaned image and metadata to IPFS and prepares calldata.
5. The token identity changes only when the owner Safe executes that calldata onchain.

Contract events are canonical. Neon is a moderation workflow and event-index cache, never the source of truth for token state.

## Deployment posture

This repository intentionally contains no deployed address, production secret, curve economics, migration target, Safe transaction, or active Mainnet configuration. Follow [the launch gates](docs/LAUNCH_GATES.md) in order. Burns are irreversible even when a proposal is rejected or outbid.

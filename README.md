# VOIDCOIN

> **Active rebuild: Zora V3.** V1 and V2 contracts are preserved as immutable history, but their custom purchase routes are retired. The next token is a Zora Content Coin on Base with a separate competitive-burn identity controller. See [`docs/ZORA_V3_LAUNCH.md`](docs/ZORA_V3_LAUNCH.md). No V3 Mainnet broadcast is included or authorized by the current branch.

VOIDCOIN is a Base-native, escalating-burn identity protocol. V2 launches as **VOIDCOIN (`VOID`)** with a fixed one-billion supply and a real Uniswap v3 VOID/USDC market from its first block. The first challenge burns 1,000,000 VOID, initially priced at approximately $1. Every takeover must clear both the previous record plus 250,000 VOID and the previous record plus 10%; the larger rule wins. A challenger may add up to a 2,000,000 VOID strategic premium. The current record holder controls the private rename proposal, while the owner Safe alone may apply an acceptable name, ticker, and ERC-1046-style metadata URI.

The website purpose and URL are permanent. Its displayed name, ticker, image, header, hero, and browser title always follow the current approved token identity.

> **Launch blocker:** VOIDCOIN / VOID has existing cryptocurrency and trademark usage. Mainnet liquidity, public promotion, and production activation require legal clearance or explicit acceptance of that collision.

## Repository

- `src/app` — Next.js App Router website, wallet flow, admin moderation, and API routes
- `src/lib` — contract client, signature auth, image sanitization, Neon, Blob, IPFS, email, and webhook helpers
- `contracts/src/VOIDCoin.sol` — non-upgradeable ERC-20 identity contract
- `contracts/src/VOIDCoinV2.sol` — V2 fixed-plus-percentage takeover escalation
- `contracts/src/VOIDV2Launch.sol` — atomic token deployment and visible token-only Uniswap v3 market
- `contracts/src/VOIDV2BuyRouter.sol` — stateless ETH → WETH → USDC → VOID purchase path
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

The public interface renders in safe preview mode without service credentials. Mutation routes fail closed until their required environment variables exist. Once the reviewed V2 addresses are configured, the site quotes the real Uniswap route and submits ETH purchases through the stateless V2 buy router. Set `NEXT_PUBLIC_SITE_URL` before preview/production review so canonical and social metadata point to the correct deployment.

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

The V2 deployment creates the token, a 12-month 2% creator vesting wallet, a 12-month LP-position locker, a token-only VOID/USDC Uniswap v3 position, and a stateless ETH buy router. The starting pool tick targets roughly $0.000001 per VOID, so the first 1,000,000-token takeover costs approximately $1 before live price movement. It requires no creator-funded ETH or USDC liquidity. Buyers route ETH through the official Base WETH/USDC market into the visible VOID/USDC pool. Buys move the price upward and sells move it downward; the protocol does not falsely promise a monotonically increasing market price.

The already-deployed V1 curve and graduation contracts remain preserved in this repository and on Base. They are legacy scope and are not overwritten by V2. See [`docs/V2_DESIGN.md`](docs/V2_DESIGN.md) and [`docs/V2_AUDIT_HANDOFF.md`](docs/V2_AUDIT_HANDOFF.md).

The former V1 graduation design is documented in [`docs/UNISWAP_MIGRATION.md`](docs/UNISWAP_MIGRATION.md) and [`docs/CURVE_PARAMETERS.md`](docs/CURVE_PARAMETERS.md) for historical verification. Neither mechanism is used by V2.

The deployment does not create or control the production Safe, unpause rename slots, broadcast itself, or deploy the website. V2 Mainnet broadcast remains separately approval-gated after an independent review of the new V2 delta.

The exact Base Mainnet rehearsal, broadcast, verification, and post-deploy checklist is in [`docs/MAINNET_DEPLOYMENT.md`](docs/MAINNET_DEPLOYMENT.md).

## Moderation lifecycle

1. The browser requests a short-lived HMAC challenge and verifies ownership with an EIP-191 wallet signature.
2. The server validates the real image format, decodes it with `sharp`, strips metadata, stores the clean asset in private Blob storage, and computes the exact onchain commitment.
3. The contract enforces a bounded range through `burnForRename`: 1,000,000 VOID initially, then the larger of the prior record plus 250,000 VOID and the prior record plus 10%. A challenger may add up to 2,000,000 VOID above that live minimum; the chosen amount becomes the record and is bound into the private commitment. A stale or above-cap submission reverts before burning. A new record immediately supersedes any pending leader.
4. The moderator enters `/admin` through an allowlisted magic link. Request changes lets the current record holder replace the proposal without burning again. Approval publishes the cleaned asset, then requires the burner to bind the exact final IPFS metadata URI without another burn.
5. After that authorization, the application prepares an ordered Safe batch that briefly locks the record and applies the identity. The token changes only when the Safe executes it onchain.

Contract events are canonical. Neon is a moderation workflow and event-index cache, never the source of truth for token state.

## Deployment posture

V1 is deployed, but this V2 branch intentionally contains no V2 Mainnet address or broadcast authorization. The new V2 delta requires independent review. Follow [the V2 launch gates](docs/V2_LAUNCH_GATES.md) in order. Burns are irreversible even when a proposal is rejected or outbid.

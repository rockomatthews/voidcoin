# Security model

## Contract authority

The owner is intended to be a multisignature Safe. It may apply a commitment-matched skin and pause or resume opening new rename slots. It cannot mint, confiscate, blacklist, tax, or pause token transfers. The contract is non-upgradeable. Ownership transfer uses `Ownable2Step`.

Each final commitment binds `chainid`, token address, burn ID, burner, exact burn amount, proposed name, proposed symbol, cleaned image hash, exact metadata URI hash, and a random salt. The burner authorizes the final IPFS URI with `replaceCommitment` after moderation and publication; this requires no additional burn. A valid current-record burn is required for any metadata change. Burns never reverse, including when a later challenger supersedes a pending proposal.

The caller cannot burn below the record threshold. `burnForRename` requires at least 1,000,000 VOID for the first record, then at least `recordBurn + 250,000 VOID`. A challenger may voluntarily burn more; that exact amount becomes the new record and is commitment-bound. A stale transaction reverts before burning when its chosen amount no longer clears the live minimum.

`npm run contracts:security` is the canonical static-analysis command. It analyzes `VOIDLaunch` and its entire dependency graph with Slither, direct `solc`, and the exact 0.8.30 compiler. This avoids the unresolved inheritance references produced by the current Foundry build-info ingestion path. The command fails closed when the expected compiler or Slither is unavailable, and CI runs it on every push and pull request.

`VOIDLaunch` performs the genesis allocation atomically: 98% enters the continuous buyer-funded curve and 2% enters a non-transferable creator-beneficiary vesting contract. Vesting starts only after successful graduation and runs linearly for 12 months. The production Safe is installed directly as token and curve owner; the launch contract never owns either. The curve charges 1% in each direction, accounts reserves internally, remains open after reaching the threshold, and closes only after a successful Safe-triggered migration. Failed migration calls roll back without closing trading.

## Private moderation data

Unapproved text, email addresses, salt values, and images remain offchain. Image payloads are capped before decoding, checked by decoded format and dimensions, and re-encoded to remove unnecessary metadata. Private Blob URLs and tokens must never reach client bundles, logs, or public database responses. Rejected assets require a scheduled deletion process after 30 days; the operator must verify that job before activation.

## Authentication

Wallet challenges and admin links are short-lived HMAC tokens. The server verifies wallet signatures. Admin sessions are HttpOnly, Secure in production, and SameSite Strict. The single allowlisted email is checked before link creation and when reading a session. Production must add rate limiting to authentication, upload, confirmation, and webhook routes.

## Webhooks and idempotency

Alchemy signatures are checked over the raw body. Receipt IDs are stored uniquely before processing. Notification mail uses a deterministic idempotency key. The direct confirmation endpoint independently validates the receipt and decoded `RenameBurned` event.

## Known operational risks

- Wallets, explorers, Uniswap surfaces, and market-data sites can cache ERC-20 metadata after an approved change.
- IPFS publication is effectively irreversible; moderation must happen before pinning.
- A prepared Safe transaction is not approval until its threshold executes and the event confirms.
- Technical review does not evaluate securities, trademark, consumer-protection, tax, sanctions, or money-transmission obligations.
- Bonding-curve configuration is economic code. The virtual reserve controls price and slippage; the threshold controls migration eligibility. Graduation uses the official Base Uniswap v3 position manager, a fixed 1% pool fee, full-range ticks, a 99.9% minimum use requirement for both assets, and immutable 12-month NFT custody. The adapter and locker still require independent semantic review even though the live-state Base Mainnet-fork rehearsal passes.

## Static-analysis baseline

The prior zero-finding Slither run at commit `18e79a24576fe2a028bf17706342989e96fec0d8` was only a syntactic baseline; the independent phase-one review subsequently demonstrated semantic Critical and High issues. Static analysis remains useful supporting evidence but is never security clearance. The remediated contracts, frozen migration target, parameters, Safe, and deployment calldata all require professional retesting before Mainnet.

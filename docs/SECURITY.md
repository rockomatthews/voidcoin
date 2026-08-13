# Security model

## Contract authority

The owner is intended to be a multisignature Safe. It may apply a commitment-matched skin and pause or resume opening new rename slots. It cannot mint, confiscate, blacklist, tax, or pause token transfers. The contract is non-upgradeable. Ownership transfer uses `Ownable2Step`.

Each commitment binds `chainid`, token address, burn ID, burner, proposed name, proposed symbol, cleaned image hash, and a random salt. A valid active burn is required for any metadata change. Burns never reverse.

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

## Static-analysis baseline

Slither runs clean across 101 non-timestamp detectors. Its timestamp detector flags the explicit 72-hour expiry and two-minute cooldown comparisons; those comparisons are the intended protocol mechanic, tolerate normal Base timestamp drift, and never determine token transfers outside the fixed burn or create value for the block producer. An independent review remains a Mainnet gate.

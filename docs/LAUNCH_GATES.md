# Launch gates

No later gate implies approval of an earlier one. Record the approver, timestamp, network, addresses, transaction hashes, and artifacts for every gate.

## 1. Local verification

- Application lint, unit tests, and production build pass.
- Foundry unit, fuzz, invariant, and static-analysis checks pass.
- Upload privacy, authorization, duplicate event, and webhook retry tests pass.
- Desktop, mobile, keyboard, screen-reader, and reduced-motion review is complete.

## 2. Base Sepolia lifecycle

- Deploy the token paused and verify source.
- Deploy a test Safe and complete the two-step ownership acceptance.
- Exercise approval, requested changes, replacement commitment, expiry, cooldown, wrong network, rejected transaction, and insufficient balance.
- Confirm the deployer retains no owner authority.
- Test event indexing, email idempotency, private assets, IPFS publication, and decoded Safe calldata.

## 3. Independent security review

- Resolve every Critical and High issue.
- Document accepted Medium and Low issues.
- Freeze reviewed bytecode, dependencies, compiler settings, and deployment scripts.

## 4. Mainnet contracts and Safe

- Obtain legal/name clearance or explicitly accept the VOIDCOIN / VOID collision.
- Approve the production Safe address and threshold.
- Approve the 10% vesting beneficiary and exact start date.
- Deploy with rename slots paused, verify source, transfer ownership, and have the Safe call `acceptOwnership()`.
- Independently verify bytecode, allocation, vesting, and zero deployer authority.

## 5. Buyer-funded bonding curve

- Decode and explicitly approve every Uniswap Liquidity Launcher LBP parameter, including auction duration, starting and ending prices, reserved token amount, migration block, currency, fee, tick spacing, allocation schedule, recovery recipient, and position recipient.
- Verify the exact canonical Liquidity Launcher, Permit2, and LBPStrategy addresses for the target Base network against the reviewed Uniswap release.
- Confirm the curve receives exactly 900,000,000 VOID and the 12-month vesting wallet receives exactly 100,000,000 VOID.
- Buyers—not the creator—supply the ETH accumulated by the curve. Confirm the configured migration moves the approved share of that ETH plus reserved VOID into the v4 position.
- Set the LP position recipient to an approved permanent or time-locked custody contract and verify the resulting position ownership after migration.
- Exercise Uniswap's documented migration-failure recovery path on Base Sepolia before Mainnet.

## 6. Production services

- Supply the domain, production RPC, Alchemy signing key, Neon database, private Blob store, Pinata account, Resend sender, admin email, WalletConnect project ID, and authentication secret.
- Apply the migration and configure the verified webhook URL.
- Review Vercel Preview first. Verify canonical, Open Graph, X, iMessage preview, security headers, logs, and private routes.
- Promote that exact tested artifact to Production.

## 7. Activation

- Confirm monitoring, moderation availability, incident response, and asset-retention jobs.
- Have the Safe unpause new rename slots.
- Announce only after the public application and canonical contract state agree.

# Launch gates

No later gate implies approval of an earlier one. Record the approver, timestamp, network, addresses, transaction hashes, and artifacts for every gate.

## 1. Local verification

- Application lint, unit tests, and production build pass.
- Foundry unit, fuzz, invariant, and static-analysis checks pass.
- `npm run contracts:security` completes with zero Slither findings and no parser errors.
- Verify the contract-enforced burn sequence is exactly 1M, 2M, 3M, and onward and cannot be caller-selected.
- Upload privacy, authorization, duplicate event, and webhook retry tests pass.
- Desktop, mobile, keyboard, screen-reader, and reduced-motion review is complete.

## 2. Local Base Mainnet-fork rehearsal

- Rehearse the deployment against a local Base Mainnet fork without publishing contracts to another chain.
- Rehearse migration through Base's official Uniswap v3 position manager and verify the NFT is registered in the immutable locker for 365 days from graduation.
- Exercise direct production Safe ownership from construction with local impersonation.
- Exercise approval, requested changes, replacement commitment, successive record challenges, wrong network, rejected transaction, and insufficient balance.
- Confirm the deployer retains no owner authority.
- Test event indexing, email idempotency, private assets, IPFS publication, and decoded Safe calldata.

## 3. Independent security review

- Resolve every Critical and High issue.
- Document accepted Medium and Low issues.
- Freeze reviewed bytecode, dependencies, compiler settings, and deployment scripts.

## 4. Mainnet contracts and Safe

- Obtain legal/name clearance or explicitly accept the VOIDCOIN / VOID collision.
- Approve the production Safe address and threshold.
- Approve the 2% creator treasury beneficiary; verify vesting cannot start before successful graduation and then runs for 12 months.
- Deploy with rename slots paused and verify source. Confirm the Safe owns the token and curve immediately and the deployer never holds protocol authority.
- Independently verify bytecode, allocation, vesting, and zero deployer authority.

## 5. Buyer-funded continuous bonding curve

- Explicitly approve the virtual ETH reserve and buyer-funded graduation threshold. The migration path is fixed to Base Uniswap v3, a 1% pool fee, full-range ticks, the Safe as bounded-dust recipient, and the repository's immutable 12-month position locker. There is no auction duration or end price.
- Confirm the continuous curve receives exactly 980,000,000 VOID and the graduation-triggered 12-month treasury receives exactly 20,000,000 VOID.
- Confirm the immutable curve fee is exactly 1% on buys and 1% on sells, with fees retained in accounted reserves.
- Buyers—not the creator—supply every real ETH deposit. Confirm the reviewed adapter places at least 99.9% of ETH and remaining VOID into the intended Uniswap position.
- Verify the LP NFT is owned by `VOIDPositionLocker`, its unlock timestamp is exactly 365 days after graduation, and its immutable beneficiary is the production Safe.
- Exercise buy, sell, forced-asset isolation, threshold eligibility, continued trading after threshold, failed migration rollback, and successful venue migration on a local Base Mainnet fork before publishing the production deployment.

## 6. Production services

- Supply the domain, production RPC, Alchemy signing key, Neon database, private Blob store, Pinata account, Resend sender, admin email, WalletConnect project ID, and authentication secret.
- Apply the migration and configure the verified webhook URL.
- Review Vercel Preview first. Verify canonical, Open Graph, X, iMessage preview, security headers, logs, and private routes.
- Promote that exact tested artifact to Production.

## 7. Activation

- Confirm monitoring, moderation availability, incident response, and asset-retention jobs.
- Have the Safe unpause new rename slots.
- Announce only after the public application and canonical contract state agree.
- Add an external Base trading link only after the live pool and token address are independently verified; the site itself never embeds a purchase form.

# Launch gates

> Historical V1 launch gates. VOIDCOIN V2 does not use the curve or graduation system described below. Use `V2_LAUNCH_GATES.md` for the active rebuild.

No later gate implies approval of an earlier one. Record the approver, timestamp, network, addresses, transaction hashes, and artifacts for every gate.

## 1. Local verification

- Application lint, unit tests, and production build pass.
- Foundry unit, fuzz, invariant, and static-analysis checks pass.
- `npm run contracts:security` completes with zero Slither findings and no parser errors.
- Foundry is pinned to v1.7.1 in CI, and `forge fmt --check` passes under that exact version.
- The clean graduation seed uses exactly 0.1% of `graduationLiquidityQuote().tokensForLiquidity` and 0.1% of accounted ETH, not 0.1% of the raw token reserve.
- A pending migration change blocks graduation, an accepted replacement cannot reuse the prior seed, and permissionless graduation is impossible until the Safe seeds the active target.
- Verify the contract-enforced floor is 1M initially and the current record plus 250K thereafter. Confirm a challenger may burn up to 2M above the live floor, the chosen amount becomes the record, and amounts outside that range revert before burning.
- Upload privacy, authorization, duplicate event, and webhook retry tests pass.
- Desktop, mobile, keyboard, screen-reader, and reduced-motion review is complete.

## 2. Local Base Mainnet-fork rehearsal

- Rehearse the deployment against a local Base Mainnet fork without publishing contracts to another chain.
- Rehearse migration through Base's official Uniswap v3 position manager and verify the NFT is registered in the immutable locker for 365 days from graduation.
- Run the dedicated fork suite without skips. Prove the virgin-pool path needs no swap, then prove the atomic executor recovers both a 0.25 ETH post-seed curve buy and hostile pre-initialization using live Uniswap contracts.
- Configure the required `BASE_MAINNET_RPC_URL` repository secret. CI must fail when it is absent; do not use a rate-limited public fallback as release evidence.
- Exercise direct production Safe ownership from construction with local impersonation.
- Exercise approval, requested changes, replacement commitment, successive record challenges, wrong network, rejected transaction, and insufficient balance.
- Confirm the deployer retains no owner authority.
- Test event indexing, email idempotency, private assets, IPFS publication, and decoded Safe calldata.

## 3. Independent security review

- Resolve every Critical and High issue.
- Obtain a professional retest of F-01 and F-02 against the exact frozen remediation commit and require both to be closed.
- Document accepted Medium and Low issues.
- Freeze reviewed bytecode, dependencies, compiler settings, and deployment scripts.

## 4. Mainnet contracts and Safe

- Obtain legal/name clearance or explicitly accept the VOIDCOIN / VOID collision.
- Approve the production Safe address and threshold.
- Verify onchain that the Safe's active fallback handler accepts ERC-721 safe transfers; otherwise the locked LP position cannot be released after 365 days.
- Record and monitor that fallback handler throughout the 365-day lock. Changing it requires proving the replacement still accepts ERC-721 safe transfers before the Safe executes the change.
- Approve the 2% creator treasury beneficiary; verify vesting cannot start before successful graduation and then runs for 12 months.
- Deploy with rename slots paused and verify source. Confirm the Safe owns the token and curve immediately and the deployer never holds protocol authority.
- Independently verify bytecode, allocation, vesting, and zero deployer authority.
- Record the public `DEPLOYER_ADDRESS`, predict the full deployment address set from its pending nonce, and publish genesis metadata containing the predicted token contract address and permanent `https://voidcoin.fun` website.
- Require `npm run genesis:verify` immediately before the dry run and Mainnet broadcast. A nonce change or metadata-URI mismatch blocks deployment.

## 5. Buyer-funded continuous bonding curve

- Verify the frozen 100 ETH virtual reserve, 1 ETH maximum purchase, and 25 ETH buyer-funded graduation threshold. The migration path is fixed to Base Uniswap v3, a 1% pool fee, a ratio-matched 0.1% seed for each Safe-approved active migration target, full-range ticks, the Safe as bounded-dust recipient, and the repository's immutable 12-month position locker. There is no auction duration or end price.
- Confirm the continuous curve receives exactly 980,000,000 VOID and the graduation-triggered 12-month treasury receives exactly 20,000,000 VOID.
- Confirm the immutable curve fee is exactly 1% on buys and 1% on sells, with fees retained in accounted reserves.
- Buyers—not the creator—supply every real ETH deposit. Confirm unused seed assets return to the curve and the reviewed adapter places at least 99.9% of remaining ETH and VOID into the intended final Uniswap position. Verify the deployed atomic executor uses the official Base SwapRouter02, spends only caller-supplied correction assets, refunds residuals, and retains zero VOID, WETH, or ETH.
- Confirm graduation burns exactly the excess unsold reserve, migrates only `ethReserve * tokenReserve / (virtualEthReserve + ethReserve)`, preserves marginal price continuity, and leaves both the curve and launch contract with zero accounted VOID.
- Verify the LP NFT is owned by `VOIDPositionLocker`, its unlock timestamp is exactly 365 days after graduation, and its immutable beneficiary is the production Safe.
- Exercise buy, sell, the 1 ETH cap, forced-asset isolation, threshold latching, continued trading after threshold, failed migration rollback, hostile pre-initialization, capped seeding, and successful venue migration on a local Base Mainnet fork before publishing the production deployment.

## 6. Production services

- Supply the domain, production RPC, Alchemy signing key, Neon database, private Blob store, Pinata account, Resend sender, admin email, WalletConnect project ID, and authentication secret.
- Apply the migration and configure the verified webhook URL.
- Review Vercel Preview first. Verify canonical, Open Graph, X, iMessage preview, security headers, logs, and private routes.
- Execute a complete approved rename through the test Safe and prove the contract's `name()`, `symbol()`, and `tokenURI()` change together; then prove the public header, hero, current image, ticker labels, browser title, social metadata, and prior-identity gallery follow that exact onchain state.
- Promote that exact tested artifact to Production.

## 7. Activation

- Confirm monitoring, moderation availability, incident response, and asset-retention jobs.
- Have the Safe unpause new rename slots.
- Announce only after the public application and canonical contract state agree.
- Add an external Base trading link only after the live pool and token address are independently verified; the site itself never embeds a purchase form.
- Verify BaseScan's Token Update displays `https://voidcoin.fun`, the approved description, and logo after source/address-ownership verification.
- After a pool transaction exists, verify DexScreener discovery and its website field. Submit consistent profiles to CoinGecko, Mobula, and The Grid; do not purchase a paid listing or metadata service without a separate spending approval.
- Verify the exact token pages at `https://base.app/coin/base-mainnet/TOKEN_ADDRESS` and `https://fomo.family/tokens/8453/TOKEN_ADDRESS`. Record evidence and escalate stale or incorrect third-party metadata to each platform with the verified BaseScan record.

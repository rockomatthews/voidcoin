# Base Uniswap v3 graduation

VOIDCOIN graduation uses the official Base Uniswap v3 deployment documented by Uniswap:

- NonfungiblePositionManager: `0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1`
- SwapRouter02: `0x2626664c2603336E57B271c5C0b26F421741e481`
- WETH9: `0x4200000000000000000000000000000000000006`
- Pool fee: 1% (`10000`)
- Tick range: full-range for the 1% tier (`-887200` to `887200`)
- Position custody: `VOIDPositionLocker`
- Lock: 365 days from the successful graduation transaction

Official address source: [Uniswap v3 Base deployments](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-base-deployments).

Before final graduation, the Safe must call `seedMigrationPool()`. The curve seeds 0.1% of the token amount calculated by `graduationLiquidityQuote()` alongside 0.1% of current accounted ETH. Those amounts have the same ratio as the final migration, so an untouched pool is initialized at the exact graduation price rather than the raw-reserve price. The adapter can also mint that bounded seed against an already initialized hostile price, returns every unused unit to the curve, and registers the seed NFT in the locker.

Seeding is the Safe's explicit graduation gate. After the Safe seeds the active migration target, `graduate()` is permissionless so execution does not depend on stale multisig calldata. A pending target change blocks graduation, and an accepted replacement target must receive its own Safe-authorized seed before it can graduate; an old seed cannot authorize a new adapter.

`VOIDGraduationExecutor` is the supported execution path whenever the pool or curve moves after seeding. It reads the active adapter, pool, current curve liquidity quote, and live Uniswap price within one transaction; determines which side must be traded; uses only the caller's bounded VOID approval or `msg.value`; places a SwapRouter02 trade with the exact target as its price limit; calls `graduate()`; then returns every unused input and swap output. If the supplied correction is insufficient, the target is wrong, or final migration fails, the entire transaction reverts. No curve reserve is spent on price correction. A heavily capitalized hostile pool may still require the Safe's delayed migration-target replacement rather than an uneconomic correction.

After the seed, the curve calculates the VOID quantity matching its final marginal price, atomically returns the excess unsold inventory to `VOIDLaunch`, and permanently burns it through the token's launch-receiver-only burn path. `VOIDUniswapV3Migration` then wraps all remaining curve ETH into WETH and mints only the price-matched VOID into the full-range position. Final graduation still reverts unless at least 99.9% of both desired assets are consumed. A failed burn or migration reverts the entire transaction, leaving supply, reserves, and trading unchanged.

The adapter has no owner, upgrade mechanism, or withdrawal function. After each mint, it registers the token ID in the locker and proves that its token, WETH, and ETH balances returned to their pre-call baselines. Unused seed assets return to the curve. Final rounding dust is capped at 0.1% by the mint minimums and is routed to the production Safe.

The locker has no owner or emergency withdrawal. It records the adapter that registered each NFT, and the curve independently verifies that the returned token ID is held and registered by its active migration target. Anyone may call `release(tokenId)` after the registered unlock time, but the NFT always transfers safely to the immutable Safe beneficiary. Because release uses `safeTransferFrom`, the production Safe must return the ERC-721 receiver selector through its configured fallback handler; deployment preflight rejects a Safe that does not. Fees remain inside the position while it is locked.

## Verification

The normal Foundry suite exercises ordering, price bounds, minimum asset use, dust routing, deflationary-token rejection, failed migration rollback, position registration, custody, and release timing.

The explicit live-state rehearsal uses the real Base Mainnet position manager without broadcasting:

```bash
forge test --root contracts \
  --fork-url "$BASE_MAINNET_RPC_URL" \
  --match-contract VOIDUniswapV3MigrationForkTest \
  -vv
```

The rehearsal contains separate regressions for: a virgin pool that graduates after twenty-five production-sized purchases with no corrective swap; the exact 0.25 ETH post-seed curve buy that previously invalidated queued graduation; a hostile pre-initialized production pool recovered through `VOIDGraduationExecutor`; direct adapter recovery; and final position custody. CI runs this command against a configured Base RPC or the public Base RPC fallback rather than counting locally skipped fork tests as evidence.

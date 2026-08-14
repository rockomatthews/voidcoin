# Base Uniswap v3 graduation

VOIDCOIN graduation uses the official Base Uniswap v3 deployment documented by Uniswap:

- NonfungiblePositionManager: `0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1`
- WETH9: `0x4200000000000000000000000000000000000006`
- Pool fee: 1% (`10000`)
- Tick range: full-range for the 1% tier (`-887200` to `887200`)
- Position custody: `VOIDPositionLocker`
- Lock: 365 days from the successful graduation transaction

Official address source: [Uniswap v3 Base deployments](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-base-deployments).

Before final graduation, the Safe must call `seedMigrationPool()`. The curve caps this one-time seed at 0.1% of each current accounted reserve. The adapter can mint that bounded seed against an already initialized hostile price, returns every unused unit to the curve, and registers the seed NFT in the locker. This converts permissionless price initialization from a gas-only permanent veto into a pool with real locked liquidity whose price can be arbitraged.

After the seed, `VOIDUniswapV3Migration` wraps the remaining curve ETH into WETH, calculates the expected pool price from the actual token/WETH migration amounts, loads the 1% pool, and mints the full-range NFT directly to the locker. Final graduation still reverts unless at least 99.9% of both desired assets are consumed. Trading remains open if seeding or final migration fails.

The adapter has no owner, upgrade mechanism, or withdrawal function. After each mint, it registers the token ID in the locker and proves that its token, WETH, and ETH balances returned to their pre-call baselines. Unused seed assets return to the curve. Final rounding dust is capped at 0.1% by the mint minimums and is routed to the production Safe.

The locker has no owner or emergency withdrawal. It records the adapter that registered each NFT, and the curve independently verifies that the returned token ID is held and registered by its active migration target. Anyone may call `release(tokenId)` after the registered unlock time, but the NFT always transfers safely to the immutable Safe beneficiary. Fees remain inside the position while it is locked.

## Verification

The normal Foundry suite exercises ordering, price bounds, minimum asset use, dust routing, deflationary-token rejection, failed migration rollback, position registration, custody, and release timing.

The explicit live-state rehearsal uses the real Base Mainnet position manager without broadcasting:

```bash
forge test --root contracts \
  --fork-url "$BASE_MAINNET_RPC_URL" \
  --match-contract VOIDUniswapV3MigrationForkTest \
  -vv
```

The rehearsal creates a fresh token and pool in local fork state, maliciously initializes it at four times the fair price, places the capped seed, arbitrages the live Base pool to the expected ratio, completes the strict final mint, and verifies both NFTs are registered in `VOIDPositionLocker`. It also confirms the 365-day unlock timestamp.

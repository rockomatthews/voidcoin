# VOIDCOIN V2 — visible takeover market

## Product outcome

V2 removes the hidden site-only bonding curve and graduation step. The token is placed in a real Base Uniswap v3 VOID/USDC pool in the deployment transaction. It is therefore a normal DEX asset from its first block and can be routed by the site, Uniswap, Base App, wallets, and aggregators once their independent indexes discover it.

The first identity takeover burns 1,000,000 VOID. The opening Uniswap tick prices VOID at approximately $0.000001, making that first record cost approximately $1 before the pool fee and price movement. The requirement after a record `R` is:

`max(R + 250,000 VOID, ceil(R × 1.10))`

A challenger may choose any whole-token amount from that floor through 2,000,000 VOID above it. The selected amount becomes the next record.

## Market construction

- Pair: VOID / native Base USDC.
- Venue: official Base Uniswap v3 position manager.
- Fee: 1% for the VOID/USDC pool.
- Starting tick: `-414600` when VOID sorts as token0, or the symmetric `414600` when VOID sorts as token1.
- Tight range: 70% of the LP allocation spans `-414600 → -391000`, or the symmetric token1 range. This preserves the approximately $1 initial takeover.
- Wide range: 30% continues from the tight boundary to tick `-230000`, or the symmetric token1 range. This removes the original ~$98,500 hard stop and extends liquidity to roughly $100 per VOID.
- Allocation: up to 980,000,000 VOID enters the two locked positions; position-manager rounding dust is burned atomically.
- Creator allocation: 20,000,000 VOID enters immutable, non-transferable vesting for the Safe, with a 30-day cliff and full vesting after 365 days.
- LP custody: both Uniswap NFTs are minted directly into `VOIDPositionLocker` for 365 days.
- Creator seed capital: zero ETH and zero USDC. Only deployment gas is required.

The pool starts exactly at one edge of a token-only range. The first USDC purchase activates the position and receives VOID. Subsequent net buys move the price upward continuously. Sells return accumulated USDC to sellers and move the price downward. This is a real two-way market; no legitimate design can guarantee the price only rises while also allowing sales.

The pool still starts with zero USDC. Code cannot create quote liquidity without capital. This launch therefore accepts a slower discovery ramp unless genuine buyers supply roughly $5,000 of initial demand; no wash trading is permitted or recommended.

## ETH purchase path

`VOIDV2BuyRouter` wraps any nonzero ETH input and calls the official Base `SwapRouter02` with a fixed route:

`WETH --0.05%--> USDC --1%--> VOID`

The router has no owner, fee withdrawal, or mutable route. The buyer supplies a minimum output. The call reverts atomically if the market moves past that limit or if any WETH, USDC, or VOID would remain in the router.

## Identity behavior

The onchain token `name()`, `symbol()`, and `tokenURI()` remain mutable only through the existing Safe-moderated commit/reveal flow. The public site continues to read those values and changes its header, hero name, ticker, image, browser title, and archive when the Safe approves a proposal.

Dynamic ticker changes remain because they are a core product requirement. Moderation must reject impersonation of existing assets, brands, or projects. Third-party classifiers can still flag a changing symbol despite moderation, and no contract can force those services to update or remove a warning.

Wallets, Base App, BaseScan, Uniswap, and market-data providers may cache ERC-20 metadata. The contract and VOIDCOIN website can update immediately, but third-party refresh timing is outside protocol control.

## V1 preservation

V1 is already deployed and is not upgraded, destroyed, or overwritten. V2 uses new contracts and new addresses. V1 holders can still use the V1 contracts according to their immutable rules. Any public deprecation or migration message is a separate product decision.

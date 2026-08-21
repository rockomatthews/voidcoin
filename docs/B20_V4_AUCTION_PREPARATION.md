# VOIDCOIN V4 auction preparation

This gate prepares a Uniswap Launch Auction for the existing Base B20 token. It does not create a Safe proposal,
collect a signature, execute an approval, create an auction, or unpause the rename controller.

## Reviewed configuration

- Chain: Base Mainnet (`8453`)
- Safe: `0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9`
- Existing B20: `0xB2000000000000000000008f1878BE4d462Bd979`
- Deposit: 1,000,000,000 VOID
- Auction sale: 500,000,000 VOID
- Reserved for the migrated v4 LP: 500,000,000 VOID
- Raise currency: native ETH
- Duration: four hours
- Floor: $1,000 fully diluted valuation, converted to ETH using the explicitly supplied preparation-time spot price
- Graduation: $10,000 fully diluted valuation, approximately $5,000 raised because half the supply is sold
- Raised funds allocated to LP: 100%
- Pool: hookless Uniswap v4, 0.25% fee, tick spacing 25, full range
- LBP strategy: direct auction-funds recipient, as required for v4 migration
- Safe: unsold-token recipient, migration-dust recipient, and failure-recovery recipient
- LP position: sent permanently to `0x000000000000000000000000000000000000dEaD`
- Identity/KYC hook: none
- Rename controller: must remain paused

The permanent LP recipient prevents the Safe from later withdrawing the migrated pool position. The tradeoff is that
no one can collect or redirect that position's fees. This does not alter the B20 name, ticker, metadata, burn, or
controller features.

## Generate the review files

Choose a start between 30 minutes and 24 hours after the latest Base block. Regenerate immediately before Safe review;
the auction block numbers and the scoped Permit2 expiration are time-sensitive.

```sh
AUCTION_START_TIME_UNIX=... \
AUCTION_ETH_USD_PRICE=... \
node --env-file=.env.local tools/uniswap-launch/prepare.mjs
```

The generator fails closed unless all of these are true:

- the RPC is Base Mainnet;
- the Safe owns the full one-billion-token supply;
- the token supply and decimals match the freeze;
- both Safe launch allowances are zero;
- the controller still points to the token and remains paused;
- the official launcher, strategy, CCA factory, and Permit2 contracts have code;
- the live strategy points to the expected CCA factory;
- the target v4 pool key is neither initialized nor reserved; and
- the predicted auction address is unused.

It writes:

- `tools/uniswap-launch/auction-preparation.json`: human-review receipt and all derived values;
- `tools/uniswap-launch/safe-transaction-builder.json`: three ordered transactions for Safe Transaction Builder.

For the full atomic Safe rehearsal, start Base's official patched Anvil on a private Base Mainnet fork, then run:

```sh
npm run b20:auction:simulate
```

The simulator refuses non-localhost RPC URLs. It imports the exact Safe file, packs the three calls into the canonical
Safe MultiSend delegatecall, executes it through the production Safe with two impersonated owners on the private fork,
and writes `tools/uniswap-launch/safe-fork-simulation.json`. It verifies the final 500M/500M token split, zero remaining
launch allowances, the v4 pool reservation, the deployed auction parameters, a one-step Safe nonce increment, and the
still-paused controller.

## Safe review boundary

The Safe file contains one atomic batch in this order:

1. approve Permit2 for exactly 1,000,000,000 VOID;
2. approve the official LiquidityLauncher in Permit2 for exactly 1,000,000,000 VOID with a short expiration; and
3. call the official LiquidityLauncher multicall, which pulls and distributes the full deposit in the same batch.

Do not split these into separate Safe executions. A failed final call must roll back both approvals. Before any future
signature authorization, repeat the live preflight and fork simulation, confirm every address and recipient, confirm the
auction has not become stale, and compare the Safe Transaction Builder import byte-for-byte with the preparation receipt.

Controller unpause is a separate later gate and must not appear in this batch.

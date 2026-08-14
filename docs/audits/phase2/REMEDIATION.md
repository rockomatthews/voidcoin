# Phase-two remediation status

This records the remediation of the phase-two delta review delivered on 2026-08-13. It is an implementation record, not an independent audit opinion or Mainnet clearance.

## Review artifacts

- Reviewed commit: `45d6ab4a53d3b4ac8df1db0e432e36c44248cfec`
- Delivered report SHA-256: `ea9af088613faa369895705d1df4d73a2215b011cfe222e9ce0b2ffb14c3e741`
- Delivered PoC SHA-256: `d722139a04c27fade28352c00f03f8749eebc16958dba15f25fcd661e2578d46`
- Real Base confirmation: the hostile pre-initialization reproduced against the deployed NonfungiblePositionManager before remediation.

## Finding disposition

| Finding | Remediation |
| --- | --- |
| C2-01 hostile pre-initialization | Added a Safe-triggered, one-time seed capped at 0.1% of each current accounted reserve. Unused seed assets return exactly to the curve. The seed position is locked and makes price movement require real liquidity instead of a gas-only initialization. Final migration retains 99.9% minimum use. A real Base fork initializes the pool at 4x fair price, seeds it, arbitrages it to the migration ratio, and completes the strict mint. |
| H2-01 replacement and custody | Removed the locker's immutable single-adapter gate. The locker records the actual registrar, and `graduate()` verifies the returned NFT is owned by the immutable locker and registered by the active migration target. Release uses `safeTransferFrom`. |
| H2-02 sandwich exposure | Production virtual reserve is 100 ETH and individual buys are capped at 1 ETH. A regression test splits a 40 ETH attacker position across forty transactions around a maximum-size victim and proves the attacker loses. The cap is not represented as a universal MEV guarantee. |
| M2-01 terminal strategic burn | Strategic overburn remains available but is capped at 2,000,000 VOID above the live minimum. Both the contract and private-intake application enforce the same maximum. |
| M2-02 threshold griefing | `thresholdReachedAt` latches on the first genuine reserve crossing. Later sells do not revoke migration eligibility and trading remains open until successful migration. |
| M2-03 single-use approval lock | The Safe can reacquire a six-hour approval lock after the prior lock expires and before the slot TTL expires. |
| L2-01 migration dust | Final dust remains bounded to 0.1% and routed to the Safe. Seed leftovers do not route to the Safe; they return to the curve. This residual final-dust behavior remains disclosed. |
| L2-02 price bounds | The production ratio cannot plausibly reach the narrow global-tick edge. Hostile-price behavior is now covered on a real Base fork. This low-severity constant cleanup remains available for the professional retest. |
| L2-03 redeemability invariant | Added a handler invariant proving `maxSellable()` covers the buyer-held public float and a post-seed unit regression proving the same property. |
| L2-04 stale migration proposals | Added owner cancellation, a seven-day acceptance window, and a code check at acceptance. |
| L2-05 reverting quote | Retained to avoid an application ABI break; `maxSellable()` remains the explicit integration boundary. Accepted Low pending reviewer feedback. |
| I2-01 fork no-op | Non-Base execution now uses `vm.skip(true)`. The hostile-price recovery test runs explicitly against Base Mainnet fork state. |
| I2-02 price-blind mock | The real Base hostile-price fork regression is now authoritative for this path. The delivered realistic mock remains useful future test infrastructure. |
| I2-03 archived PoCs | Active unit, fuzz, invariant, and fork tests now cover the remediated behaviors instead of relying only on archived reports. |
| I2-04 finding IDs | This document preserves the review's phase-two IDs. Phase-one cross-reference cleanup remains documentation-only. |
| I2-06 junk NFTs | Permissionless registration is harmless unless the NFT is actually held by the locker; curve acceptance additionally requires registration by the active target. |
| I2-07 unsafe NFT release | Replaced `transferFrom` with `safeTransferFrom`. |

## Frozen approved parameters

- Virtual ETH reserve: 100 ETH.
- Maximum purchase: 1 ETH per transaction.
- Graduation threshold: 25 real ETH.
- Pool seed cap: 0.1% of each current accounted reserve, once.
- Graduation burn: permanently destroy excess unsold curve inventory so the final LP token/ETH ratio matches the curve's marginal price.
- Rename floor: 1,000,000 VOID initially, then record plus 250,000 VOID.
- Strategic premium cap: 2,000,000 VOID above the current floor.

## Verification

- 46 Foundry tests pass; three Base fork tests explicitly skip outside a fork.
- Every handler invariant runs 128,000 calls, including full-float redeemability.
- The hostile pre-initialization recovery test and the exact 25 ETH production graduation lifecycle pass against deployed Base Uniswap contracts without broadcasting. The production lifecycle burns the calculated excess, migrates only the price-matched token quantity, and leaves the curve and launch receiver with zero token balances.
- Slither reports zero results for the launch graph, migration adapter, and position locker using Solidity 0.8.30.
- 12 application tests, ESLint, TypeScript, and the production Next.js build pass.

## Remaining Mainnet blockers

1. Independent professional retest of the new frozen commit and deployment calldata.
2. Production Safe address and configuration.
3. Final permanent genesis IPFS metadata.
4. Professional review of the newly added scoped launch-reserve burn and exact price-continuity formula.
5. No deployment, activation, buyer funding, or Safe execution occurs until those gates close.

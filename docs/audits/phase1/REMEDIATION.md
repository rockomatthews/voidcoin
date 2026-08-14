# Phase-one remediation status

This document maps the independent phase-one report to the current `codex/audit-remediation` branch. It is an implementation record, not an auditor retest or Mainnet clearance.

## Approved economics

- Fixed supply: 1,000,000,000 VOID.
- Public bonding curve: 980,000,000 VOID (98%).
- Creator treasury: 20,000,000 VOID (2%).
- Curve fee: 1% on buys and 1% on sells, retained in the internally accounted reserves.
- Rename escalation: a 1,000,000 VOID initial floor, then at least 250,000 VOID above the previous record. A challenger may choose a larger commitment-bound burn to set a harder record.
- Curve parameters: 2 ETH virtual reserve and 25 ETH buyer-funded graduation threshold.
- Treasury release: impossible before successful graduation, then linear over 12 months to the immutable beneficiary.

## Finding disposition

| Finding | Remediation |
| --- | --- |
| C-01 migration freeze and unsafe immutable target | Threshold no longer closes trading. Failed migration reverts atomically and leaves trading open. Migration targets use a two-day propose/accept delay, require deployed code, and ownership cannot be renounced. Successful migration must return a nonzero outcome identifier and consume the exact accounted ETH and token amounts. The final adapter remains a mandatory phase-two review item. |
| H-01 forced ETH corrupts reserves/graduation | Added internal `ethReserve` and `accountedTokenReserve`; direct or forced donations do not affect price or migration eligibility and can only be swept as excess. |
| H-02 fee-less, deadline-free trades | Added immutable 1% fees, mandatory nonzero minimum output, caller deadline checks, and pool-favoring rounding. |
| H-03 treasury drains buyer curve | Reduced treasury from 10% to 2%. Replaced OpenZeppelin `VestingWallet` with a non-transferable beneficiary contract that releases nothing before successful graduation and therefore cannot sell into the active curve. |
| M-01 large exits fail silently | `quoteSell` explicitly reverts when the real ETH reserve cannot pay an exit and `maxSellable()` exposes the conservative gross-token boundary. |
| M-02 metadata URI unbound | Final commitments now include `keccak256(metadataURI)`. Moderation publishes approved content, then the burner authorizes that exact final commitment through `replaceCommitment` without another burn. |
| M-03 approval can be superseded | Added a one-time six-hour Safe-controlled record lock. The application prepares lock and approval as an ordered Safe batch. |
| M-04 rename slots never expire | Added a 72-hour expiry enforced by replacement and approval paths plus permissionless `expireSlot()`. |
| M-05 migration target not validated | Constructor and delayed replacement require deployed code. Final venue bytecode and behavior remain blocked on phase-two review. |
| L-01 launch ownership handoff | `VOIDLaunch` installs the deployed Safe directly as token and curve owner; the launch/deployer never owns protocol contracts. |
| L-02 rounding favors trader | Buy and sell pricing use ceiling division and fees absorb rounding in favor of reserve solvency. |
| L-03 unreachable record check | Removed. |
| L-04 incomplete constructor validation | Safe and migration target must contain code; all critical addresses and economic parameters are validated. |
| L-05 transferable/renounceable vesting | Replaced with immutable beneficiary vesting that has no ownership functions. |
| L-06 zero slippage in tests | Production calls require nonzero minimum output and deadline. Tests use exact quotes or explicit bounds. |

## Verification performed

- 38 Foundry tests pass across unit, fuzz, invariant, migration-adapter, strategic-overburn, and position-locker suites.
- Each invariant campaign executes 128,000 handler calls.
- Curve invariants prove reserves remain backed, trading cannot reduce the pool invariant, and the curve cannot create token supply.
- The application passes ESLint, 12 Vitest tests, TypeScript checking, the production Next.js build, and a production dependency audit with zero reported vulnerabilities.
- Slither runs fail-closed with the exact Solidity 0.8.30 compiler against the complete launch graph. A zero-finding result is supporting evidence only, not a substitute for semantic review.
- A read-only Base Mainnet fork test creates a real Uniswap v3 full-range position in the immutable locker, and the complete non-broadcasting deployment rehearsal succeeds with the frozen 2 ETH / 25 ETH parameters.

## Still blocked before Mainnet

1. Supply and verify the deployed production Safe, final genesis IPFS metadata, and deployment calldata.
2. Have the professional reviewer rerun the supplied proof cases and review the Base Uniswap v3 adapter plus immutable 12-month position locker.
3. Repeat the already-passing live-state Base Mainnet-fork rehearsal with the final Safe and economic parameters.
4. Resolve all retest Critical/High findings before any broadcast or buyer funding.

# VOIDCOIN phase-two retest request

Please retest frozen commit `de75754e2b842f2f5c072210957f252b1b1f7e2e` on `codex/audit-remediation` against the findings in `VOIDCOIN_Phase1_Security_Review.md`. The original proof file is preserved beside this request as `AuditPoC.t.sol`; it targets the frozen phase-one interfaces and is intentionally not part of the active test directory.

## Decisions now frozen for this retest

- 1% immutable buy fee and 1% immutable sell fee.
- 98% of the one-billion supply allocated to the buyer-funded curve.
- 2% allocated to an immutable creator beneficiary, with release blocked until successful graduation and then vested over 12 months.
- Trading remains open after the threshold and after failed migration attempts; only successful migration closes the curve.
- Two-day timelock for changing the migration target.
- 72-hour rename proposal lifetime and one-time six-hour approval lock.
- Rename burns have a 1,000,000 VOID initial floor. Each takeover must exceed the current record by at least 250,000 VOID, while allowing a challenger to choose a larger commitment-bound strategic burn.
- Curve parameters are fixed at a 2 ETH virtual reserve and 25 ETH buyer-funded graduation threshold.
- Final burner commitment binds the exact approved metadata URI hash.
- Graduation uses `VOIDUniswapV3Migration` with Base's official Uniswap v3 position manager, a fixed 1% pool fee, full-range ticks, and a 99.9% minimum use requirement for both assets.
- The resulting position is atomically registered in `VOIDPositionLocker` and cannot be released to the immutable Safe beneficiary for 365 days from graduation.

## Requested retest

1. Re-run or adapt all 19 phase-one proof cases against the new interfaces and report which are closed, changed, or still reproducible.
2. Review the new internal reserve accounting, fee/rounding math, `maxSellable`, migration state ordering, adapter post-conditions, target timelock, and excess sweeping.
3. Review `VOIDTreasuryVesting` for any pre-graduation transfer path, beneficiary mutability, arithmetic edge case, or way to manipulate the graduation start.
4. Review direct Safe ownership at deployment and confirm the deployer/launch contract retains no authority.
5. Review the metadata-URI authorization round trip and approval lock for replay, supersession, expiration, or griefing paths.
6. Review the new curve handler invariants and identify any missing economic property.
7. State explicitly whether every Critical and High finding is closed in the reviewed commit.
8. Review `VOIDUniswapV3Migration`, `VOIDPositionLocker`, and the live-state fork test, including pool pre-initialization griefing, price manipulation, token ordering, sqrt-price math, minimum-amount enforcement, dust routing, NFT custody, and release timing.

The Base venue adapter, 1% full-range pool configuration, 12-month locker, burn escalation, and curve economics are frozen for this retest. The production Safe, final genesis IPFS URI, and final deployment calldata remain deployment-specific inputs and require a final delta review before broadcast.

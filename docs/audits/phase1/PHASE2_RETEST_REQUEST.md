# VOIDCOIN phase-two retest request

Please retest the current `codex/audit-remediation` branch against the findings in `VOIDCOIN_Phase1_Security_Review.md`. The original proof file is preserved beside this request as `AuditPoC.t.sol`; it targets the frozen phase-one interfaces and is intentionally not part of the active test directory.

## Decisions now frozen for this retest

- 1% immutable buy fee and 1% immutable sell fee.
- 98% of the one-billion supply allocated to the buyer-funded curve.
- 2% allocated to an immutable creator beneficiary, with release blocked until successful graduation and then vested over 12 months.
- Trading remains open after the threshold and after failed migration attempts; only successful migration closes the curve.
- Two-day timelock for changing the migration target.
- 72-hour rename proposal lifetime and one-time six-hour approval lock.
- Final burner commitment binds the exact approved metadata URI hash.

## Requested retest

1. Re-run or adapt all 19 phase-one proof cases against the new interfaces and report which are closed, changed, or still reproducible.
2. Review the new internal reserve accounting, fee/rounding math, `maxSellable`, migration state ordering, adapter post-conditions, target timelock, and excess sweeping.
3. Review `VOIDTreasuryVesting` for any pre-graduation transfer path, beneficiary mutability, arithmetic edge case, or way to manipulate the graduation start.
4. Review direct Safe ownership at deployment and confirm the deployer/launch contract retains no authority.
5. Review the metadata-URI authorization round trip and approval lock for replay, supersession, expiration, or griefing paths.
6. Review the new curve handler invariants and identify any missing economic property.
7. State explicitly whether every Critical and High finding is closed in the reviewed commit.

The final Base venue migration adapter, production Safe, economic parameters, position recipient, and deployment calldata are still unfrozen. They require a subsequent delta review and Mainnet-fork rehearsal before deployment.


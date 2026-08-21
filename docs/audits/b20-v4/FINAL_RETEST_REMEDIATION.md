# VOIDCOIN V4 final retest remediation

Date: August 21, 2026

The independent final retest of commit `ac61d3a4a9229883b77f18e38402b090870de20c` concludes that no unresolved
Critical or High finding remains in either the contracts or launch path. The production Solidity freeze at
`c7ac786625a92b4c626a5cbfc15816dd2d9a16d1` remains unchanged.

## N-1 closure

The verifier now requires each parsed gateway metadata document to be structurally identical to `receipt.metadata`
after verifying that the response bytes hash to the advertised CID. This binds the human-readable receipt record to
the exact public document selected for the onchain `contractURI` without depending on JSON whitespace or object-key
serialization order.

The repository surface harness includes a new receipt-only mutation and requires it to fail. The auditor's independent
30-scenario harness is also rerun as a release gate; N17 must be blocked and the final deviation count must be zero.

## Accepted permanent findings

No frozen contract was changed. The operational controls requested for accepted M-1 and M-2 are mandatory in
`docs/B20_V4_SAFE_RUNBOOK.md`:

- an append-only historical-name ledger beginning with `VOIDCOIN`, with exact and case-insensitive reuse rejected; and
- two full `activeSlot()` comparisons, including `commitment`, before the Safe signs the ordered lock-and-approve batch.

The runbook also records the required post-execution checks and repeats the live Base activation/Safe preflight in the
same operator session as any future authorized broadcast or unpause.

## Verification

- Repository surface harness: 40 scenarios, 0 deviations.
- Auditor's independent surface harness: 30 scenarios, 25 blocked, 5 valid passes, 0 deviations; N17 is blocked.
- `npm run verify`: 24 app tests passed, ESLint passed, surface harness passed, Next production build passed.
- Stock Forge excluding the deliberately live-only gate: 163 passed, 0 failed, 9 skipped.
- Base patched Forge: 171 passed, 0 failed, 9 skipped, including the live-precompile banner and `V4LiveGate` 8/8.
- Slither: 0 findings across all 11 production targets.
- Production Solidity remains byte-identical to `c7ac786625a92b4c626a5cbfc15816dd2d9a16d1`.

Current delivery hashes:

```text
f5be312a5209b6fa903497ff238f83f651ab2b687b8a0a2e3267fd10d9af3ac6  scripts/verify-b20-surface-readiness.mjs
dec4c11831bd9e9d2082dea4d22259ad20ffaf6151d9d8f1675be14ffd45a0e3  scripts/surface-readiness-harness.mjs
b13222310fede6fa246da64e9c55ea4282187cc4bbae53c206280660a7c60a5f  docs/B20_V4_LAUNCH.md
64fa0a3a5437aae80a64ecf38723f917cda9d5e56140251c334082507574ec21  docs/B20_V4_SAFE_RUNBOOK.md
9addc056afb7a7d70f807c6ea376a413066648d9886f8c914b44db2863d08cf8  docs/audits/b20-v4/VOIDCOIN_V4_Final_Retest.md
```

## Informational behavior retained

The exact `links` and `market_links` schemas remain intentionally fail-closed. Adding fields or changing the expected
shape requires an explicit verifier update. Pending-request discovery remains private and UUID-based; support may
restore a user's locally lost request ID after verifying the submitting wallet, but must never enumerate another
wallet's requests or disclose private proposal data.

No deployment, metadata publication, token approval, auction, Safe transaction, or controller unpause was performed.

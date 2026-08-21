# VOIDCOIN V4 Safe runbook

This runbook is a mandatory procedural control for the accepted M-1 and M-2 contract findings. It does not authorize
deployment, a Safe signature, an auction, or controller unpause.

## Append-only used-name ledger

Reject a proposal if its exact proposed token name, or its case-insensitive form, appears below. Never delete or edit a
prior entry. Add a new entry only after the Safe transaction succeeds and an independent Base Mainnet read confirms
that `name()` and the `SkinChanged` event match.

| Sequence | Token name | Status | Base transaction |
|---:|---|---|---|
| 0 | `VOIDCOIN` | Genesis name reserved before deployment | Not deployed |

This rule prevents returning to an earlier EIP-712 domain name and reviving an unused permit signature. The Safe must
reject reuse even if the proposal otherwise has a valid burn and commitment.

## Pre-sign active-slot check

For every rename approval, the Safe operator must perform these steps in one uninterrupted operator session:

1. Read `activeSlot()` from Base Mainnet using the production controller address and a trusted Base RPC.
2. Compare `burnId`, `burner`, `burnAmount`, `commitment`, `createdAt`, `lockedUntil`, and `exists` with the approved private request. Abort on any mismatch.
3. Confirm the proposed name is absent from the append-only used-name ledger above.
4. Build a single ordered Safe batch containing `lockRenameSlot(burnId)` followed by the exact `approveRename(...)` calldata produced for that same commitment.
5. Simulate the complete Safe batch against current Base Mainnet state. Abort if either call reverts or the resulting name, symbol, URI, and image hash differ.
6. Immediately before the final Safe signature, read `activeSlot()` again and compare every field, especially `commitment`, with step 2. Abort and discard the batch if anything changed.
7. After execution, confirm the transaction succeeded, the slot cleared, supply did not increase, and the token's `name()`, `symbol()`, and `contractURI()` match the approved proposal.
8. Append the confirmed name and Base transaction hash to the ledger before considering another proposal.

Never sign a lock based only on an earlier API response, screenshot, cached page, or prior simulation. A burner can
replace the commitment until the slot is locked.

## Unpause gate

Before separately proposing `setRenamePaused(false)`, confirm:

- deployment and postdeployment surface verification passed against Base Mainnet;
- the production database migration and website moderation flow passed an end-to-end smoke test;
- the ledger above still contains every confirmed historical name, beginning with `VOIDCOIN`;
- Safe operators have rehearsed the pre-sign active-slot check; and
- Base activation, chain ID, controller/token binding, Safe owners, and threshold were re-read in the same operator session.

Unpausing remains a separate Safe action and must not be bundled into deployment or market launch.

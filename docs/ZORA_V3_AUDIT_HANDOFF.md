# VOIDCOIN Zora V3 controller — independent review handoff

## Verdict requested

Confirm whether the frozen controller is suitable for Base Mainnet deployment against the already-live Zora Content Coin. Report Critical, High, Medium, Low, and Informational findings with reproducible proof-of-concept tests. Mainnet controller deployment is blocked on every unresolved Critical or High.

The Zora coin and market are already live. The controller has **not** been deployed or added as a coin owner.

## Live production dependency

- Network: Base Mainnet (`8453`)
- Zora Content Coin: `0x4A64F213558Fb0188e3FC48918948EC590A66733`
- Production Safe: `0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9`
- Creation transaction: `0x6a3d2d108621e0dd9770c65c7b9fe7d37b8b5c0f8646600cf729ae08ae2c5de7`
- Zora contract version emitted at creation: `2.6.0`
- Zora pool key hash: `0x93e16947a14ec8bc7364373f128677ca207ea408a6d73ef82b8ca92f0e6b33a9`

## Review scope

- `contracts/src/VOIDZoraSkinController.sol`
- `contracts/script/DeployZoraController.s.sol`
- `contracts/test/VOIDZoraSkinController.t.sol`
- `contracts/test/VOIDZoraSkinController.fork.t.sol`
- `src/components/burn-terminal.tsx`
- `src/app/api/requests/route.ts`
- `src/app/api/requests/[id]/confirm/route.ts`
- `src/app/api/admin/requests/[id]/route.ts`
- `src/lib/proposal.ts`

The historical V1/V2 curve, migration, Uniswap, vesting, and locker contracts are not used by Zora V3.

## Required confirmations

1. `burnForRename(expectedBurnId, burnAmount, commitment)` rejects stale prepared state before transfer, can only consume the caller-approved amount, and atomically leaves the controller with zero tokens.
2. A successful contest burn reduces the live Zora coin's `totalSupply()` by exactly the selected amount; failure rolls back transfer, burn, and record state.
3. The fixed-plus-percentage escalation and 2M strategic premium cap cannot overflow, reset, or create an unreachable rename floor under reachable supply.
4. Only the production Safe can approve metadata, pause intake, or lock a slot; ownership renunciation is disabled.
5. Adding the controller as a Zora coin owner does not create any metadata-update path outside a valid active commitment and Safe approval.
6. Commitment domain separation binds chain ID, controller, burn ID, burner, amount, name, symbol, image hash, metadata URI hash, and salt without replay or ambiguity.
7. Replacement, takeover, lock, expiry, and moderation flows cannot let a stale or superseded proposal burn against the wrong ID or change the live token.
8. External Zora calls cannot reenter or leave name, symbol, and metadata URI partially updated.
9. Direct holder burns outside the contest cannot corrupt contest accounting or escalation.
10. The deployment script validates the exact live one-billion-supply Zora coin and assigns controller ownership to the Safe from construction.
11. The frontend performs exact-amount ERC-20 approval before the controller burn and verifies the controller event from the confirmed Base receipt.
12. The live Base fork test genuinely runs against the production Zora proxy and exercises its real burn and mutable-identity implementation.

## Reproduction

```bash
forge fmt --check
forge test --match-contract VOIDZoraSkinControllerTest -vvv
set -a
source .env.local
set +a
forge test --match-contract VOIDZoraSkinControllerForkTest -vvvv
npm run verify
```

Please state explicitly whether any unresolved Critical or High remains and whether controller deployment plus subsequent Safe `addOwner(controller)` is suitable for Mainnet.

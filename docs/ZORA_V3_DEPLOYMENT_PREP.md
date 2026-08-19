# VOIDCOIN Zora V3 controller — deployment preparation

This is a preparation receipt, not deployment authorization. No controller deployment, Zora `addOwner`, controller unpause, or website deployment is authorized by this file.

## Frozen production inputs

- Chain: Base Mainnet (`8453`)
- Zora VOID token: `0x4A64F213558Fb0188e3FC48918948EC590A66733`
- Controller owner / production Safe: `0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9`
- Deployment account: `0x8A0182c099A618583e9EF98716DAcF739b3BD944`
- Prepared deployment nonce: `59`
- Predicted controller at that nonce: `0x4Ef2Cf3D27B4ec1cAFd1e28e8B9f63aC74875abD`

The address prediction is valid only while the deployment account's pending nonce remains `59` and the compiled init code is unchanged. Re-run every check below immediately before requesting broadcast authorization. Any different nonce, predicted address, source diff, Safe, token address, supply, owner result, or calldata is a launch stop.

## Verified rehearsal

The non-broadcast Foundry rehearsal on 2026-08-18 confirmed:

- the live token reports exactly `1_000_000_000 ether` total supply;
- the production Safe is currently a Zora coin owner;
- the controller is constructed paused with the production Safe as owner;
- the simulated CREATE address is `0x4Ef2Cf3D27B4ec1cAFd1e28e8B9f63aC74875abD`;
- estimated deployment gas was `2,511,406`, approximately `0.000027612537281912 ETH` at the rehearsal gas price.

Rehearse again without `--broadcast`:

```bash
set -a
source .env.local
set +a
ZORA_VOID_ADDRESS=0x4A64F213558Fb0188e3FC48918948EC590A66733 \
  forge script contracts/script/DeployZoraController.s.sol:DeployZoraController \
  --root contracts \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --sender "$DEPLOYER_ADDRESS" \
  -vvvv
```

Before any later broadcast, record `git status --short`, `git rev-parse HEAD`, the pending deployer nonce, the predicted controller address, `forge fmt --check`, the controller unit suite, and the live fork suite. The worktree must contain no tracked changes.

## Prepared post-deployment Safe calls

These calls are intentionally **not executed**. They are valid only if the controller actually deploys at the predicted address and its source is verified first.

1. Target Zora token `0x4A64F213558Fb0188e3FC48918948EC590A66733`:

   - `addOwner(0x4Ef2Cf3D27B4ec1cAFd1e28e8B9f63aC74875abD)`
   - calldata: `0x7065cb480000000000000000000000004ef2cf3d27b4ec1cafd1e28e8b9f63ac74875abd`

2. Only after confirming `isOwner(controller) == true`, target controller `0x4Ef2Cf3D27B4ec1cAFd1e28e8B9f63aC74875abD`:

   - `setRenamePaused(false)`
   - calldata: `0x560ee0a40000000000000000000000000000000000000000000000000000000000000000`

Keep the second call closed until the controller deployment and source verification are complete, the Safe owner transaction is separately approved and executed, Preview is configured, and the moderation-email path is ready for the fresh-wallet acceptance test.

## Remaining explicit gates

1. Independent retest of the final expected-burn-ID remediation — completed; see `docs/audits/zora/FINAL_RETEST_RECEIPT.md`.
2. Fresh nonce/address rehearsal and bytecode/source verification plan — required immediately before broadcast.
3. Explicit authorization to broadcast the controller deployment — received on 2026-08-19 for the controller only.
4. Post-deployment source verification and ownership/paused-state receipt.
5. Separate explicit authorization for the Safe to call `addOwner(controller)`.
6. Separate decision to unpause, configure Preview, run acceptance, and promote the site.

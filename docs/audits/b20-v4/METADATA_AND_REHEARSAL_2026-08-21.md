# VOIDCOIN V4 metadata publication and deployment rehearsal

Date: 2026-08-21

Network: Base Mainnet (chain ID 8453)

Authorization: metadata publication and no-broadcast deployment rehearsal only

## Result

The final V4 metadata and logo were published to IPFS, the strict genesis and public-surface gates passed, and the exact
deployment transaction was successfully simulated with Base's patched Forge implementation. No deployment transaction was
broadcast. No token approval, auction, Safe transaction, controller unpause, or other launch transaction was executed.

This receipt is predeployment evidence, not evidence that the token is live.

## Frozen deployment inputs

- Git branch at rehearsal: `codex/o1-v4`
- Git commit at rehearsal: `fd46a7cf2eca2a1d4e1b52f5817901e2e708c949`
- Base deployer: `0x8A0182c099A618583e9EF98716DAcF739b3BD944`
- Pending deployer nonce: `62`
- B20 factory: `0xB20f000000000000000000000000000000000000`
- Deployment salt: `0x19c9a388e7bbcd4cb2094a0ee82d0523ec0672d518f4a55885792f5c5d7ad969`
- Predicted bootstrapper: `0x1c18F40FABD28BCC36c5E52f3A64c023D745FF36`
- Predicted controller: `0xaab614e99d804D9fAfCc35605791442bF120b71D`
- Predicted B20 token: `0xB2000000000000000000008f1878BE4d462Bd979`

The final read-only check at Base block `50275490` returned pending nonce `62` and empty bytecode (`0x`) at all three
predicted addresses.

## Published metadata

- Metadata: `ipfs://QmSmyp12pRoGf9pJTto91h9mHWvRtYLasbrUCxiEKzhCZJ`
- Logo: `ipfs://QmSTzmwHa3NiHhEb6EsztuvYkScVnmuts9HkFobpVbbuJu`
- Logo: PNG, 1134 by 1134 pixels
- Metadata shape: B20/ERC-7572 plus typed website, Base App, Fomo, Uniswap, DEX Screener, and BaseScan routes

`npm run b20:verify` passed against the final receipt, pending nonce, salt, predicted address, and pinned bytes.

`npm run b20:surface:verify` passed against two independent public gateways:

| Gateway | Metadata | Logo | Logo result |
| --- | ---: | ---: | --- |
| `https://gateway.pinata.cloud/ipfs` | 200 | 200 | `image/png`, 1134 by 1134 |
| `https://ipfs.io/ipfs` | 200 | 200 | `image/png`, 1134 by 1134 |

An independent Kubo v0.43.0 node imported the exact final metadata and logo bytes, reproduced both CIDs, announced both
CIDs to IPFS, and was shut down after the two-gateway gate passed.

The verifier now sends an explicit `Accept` header for JSON or PNG and permits 45 seconds for a public gateway response.
The CID, schema, byte-content, redirect, size, image-quality, route, and two-gateway assertions are unchanged. The repository
surface harness passed 40 scenarios with zero deviations, and the independent auditor harness passed 30 scenarios with zero
deviations after this transport-hardening change.

## No-broadcast Base rehearsal

Stock Forge stopped at the Base-native B20 factory because stock Forge does not implement Base's native B20 precompiles.
That expected failure did not broadcast anything.

The same script then completed using the Base-patched Forge executable without `--broadcast`, against the live Base RPC and
the exact final metadata URI. The simulation produced:

- constructor transaction nonce: `62`
- B20 supply delivered to the Safe: `1,000,000,000 ether`
- controller owner: production Safe
- controller ready: `true`
- rename contest paused: `true`
- estimated gas: `3,205,096`
- estimated cost: `0.000226229021699744 ETH`
- deployer balance observed during preflight: `0.003297489662746073 ETH`

Ignored local simulation artifacts:

- `contracts/broadcast/DeployB20V4.s.sol/8453/dry-run/run-latest.json`
- `contracts/cache/DeployB20V4.s.sol/8453/dry-run/run-latest.json`
- `assets/genesis/b20-published.json`

## Nonce incident and mandatory launch-day recheck

The first metadata prediction used nonce 61. Before rehearsal, an unrelated successful USDC transfer from the deployer mined
at nonce 61 in transaction `0xc2ffbb299d2b3edad83ba42815e59afedb892178021679af17a5bfef64aec81f`. The repository's strict gate detected the nonce
change and blocked the stale prediction. Metadata was republished for nonce 62; only the nonce-62 URI and addresses in this
document are valid.

Before any future broadcast authorization, rerun both verification gates and the Base preflight in the same operator session.
If the pending nonce is no longer 62, do not broadcast: predict again and republish metadata for the new address first.

## Remaining action boundary

No contract is deployed and V4 is not live. A future deployment requires a new, explicit authorization to broadcast. Token
approval, auction creation, Safe transactions, and controller unpause remain separate authorization gates.

Operational note: the configured QuickNode RPC credential appeared in failed local command output during this rehearsal. Rotate
that credential before authorizing a broadcast; do not reuse the exposed value.

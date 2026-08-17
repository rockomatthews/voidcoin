# Phase-four final delta disposition

This records the response to the final delta retest delivered on 2026-08-17. The reviewer concluded that no Critical or High finding remained and that the reviewed implementation was suitable for Base Mainnet subject to the enumerated production-input gates and the reviewer's Base-RPC limitation.

## Review artifacts

- Reviewed implementation commit: `870ba4b3eeeed7f929ba5d1018a8baf22994f8f3`
- Delivered report SHA-256: `3cd5671d4ff43aa485d52557de6d2f0d2521cf965415cda1b5735ed54f0c5802`
- Delivered PoC SHA-256: `11b58649ab89f9c7ad17c625151949ca545ad4b9716b1acfe71969fd5452c99b`
- Delivered Uniswap model SHA-256: `cd2a0f1fbc4ca44593c0eb538e4c57d446503f874f7dc693e54393e49350f4ff`

## Disposition

| Item | Response |
| --- | --- |
| F-01 | Closed by the reviewer. The ratio-matched seed is price-neutral and the virgin-pool path graduates directly. |
| F-02 | Closed by the reviewer. Both correction directions, rollback, donations, reentrancy, hostile pools, and refunds were exercised. |
| N-01 rounding-only exact comparison | Remediated with a maximum one-part-per-billion relative sqrt-price tolerance. The active model suite proves a fresh ratio-matched seed can execute without correction capital while larger price movement still requires correction. |
| N-02 WETH9 stipend margin | Remediated by caching canonical WETH9 immutably in the executor constructor. `receive()` performs only the immutable sender comparison. Active tests use a Base-style WETH9 `transfer` stipend and force the WETH correction/refund branch. Replacement targets reporting a different wrapped-native address fail closed. |
| N-03 Safe fallback-handler snapshot | Accepted as an operational Low. Deployment still rejects an incompatible Safe; the launch gates and runbook now prohibit unverified handler changes and require periodic onchain monitoring through the 365-day lock. |
| Formatter correction | Foundry is pinned to v1.7.1 in CI and formatting is generated and checked under that exact version. |
| Public RPC fallback | Removed. The Base fork CI step requires the `BASE_MAINNET_RPC_URL` repository secret and fails when absent. |
| Price-blind unit stubs | The delivered `UniV3Model.sol` and adapted Phase 4 proof suite are active Foundry tests, not archived evidence only. |

The three delivered files are archived byte-for-byte alongside this record. Any Mainnet broadcast remains subject to the production Safe, Safe threshold/signers, genesis IPFS URI, deployment calldata, reproducible bytecode, legal/name acceptance, gas funding, and explicit deployment authorization.

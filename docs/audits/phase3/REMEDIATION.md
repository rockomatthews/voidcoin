# Phase-three remediation status

This records the remediation of the final retest delivered on 2026-08-17. It is an implementation record, not an independent audit opinion or Mainnet clearance.

## Review artifacts

- Reviewed application commit: `93352679621e6e083c2405d4fc698784132a116c`
- Reviewed Solidity commit: `0699124bb85b10c89f121e923bf82f38aefeabba`
- Delivered report SHA-256: `e4c027ac5292b94ee6067d95bbb34673e407daf85fedcbfd55d9e63917ca22e8`
- Delivered PoC SHA-256: `72b72484284790a15bf9af3f3e393d3521ab9694ef2cffc0a3dc2bb49b6fde71`
- The exact remediation commit is recorded in `REVIEW_SCOPE.md` after the code freeze.

## Finding disposition

| Finding | Remediation |
| --- | --- |
| F-01 seed/final-price mismatch | `seedMigrationPool()` now caps VOID at 0.1% of `graduationLiquidityQuote().tokensForLiquidity`, paired with 0.1% of accounted ETH. A virgin-pool Base fork test performs twenty-five 1 ETH buys, seeds, and graduates directly with no swap. |
| F-02 stale narrow graduation window | Added `VOIDGraduationExecutor`. It reads the active curve and Uniswap state, corrects the live pool to the exact current target using only caller-bounded assets, calls graduation in the same transaction, and refunds all residual input/output. Graduation is permissionless only after the Safe seeds the active target. Pending target changes block graduation; accepted replacements require a new Safe seed. Base fork tests cover the review's exact 0.25 ETH post-seed buy and a hostile pre-initialized production pool. |
| L3-01 immutable beneficiary ERC-721 reception | `Deploy.s.sol` calls the candidate Safe's `onERC721Received` path before broadcast and refuses deployment unless the required selector is returned. The launch gates and deployment runbook require an onchain fallback-handler verification. |
| L3-02 permissionless junk positions | Accepted Low. Registration requires actual locker custody and records the caller; arbitrary deposits cannot satisfy the curve's active-adapter verification. Operational NFT noise is documented. |
| L3-03 tokens donated to `VOIDLaunch` | Accepted Low. The intentionally single-use curve burn authority remains non-reusable; unrelated donations cannot be recovered or burned. |
| L3-04 formatter failure | Corrected. `forge fmt --check` is a required local and CI gate. |
| Residual loss-making MEV griefing | Documented the measured 193–3,547 bps victim shortfall and retained mandatory nonzero slippage bounds and deadlines. No universal MEV-prevention claim is made. |
| Fork-test process gap | CI now runs the dedicated suite against a Base Mainnet RPC in addition to the ordinary local suite. Local `vm.skip(true)` results are not counted as fork evidence. |

## Verification required for freeze

- `forge fmt --check`
- full local Foundry unit, fuzz, and invariant suite
- all production migration regressions against live Base Mainnet fork state
- Slither with Solidity 0.8.30 for the launch graph, adapter, executor, and locker
- application lint, unit tests, and production build
- professional delta retest of F-01 and F-02 against the exact frozen commit

No Mainnet deployment, liquidity migration, buyer funding, or Safe execution is authorized by this document.

# VOIDCOIN phase-three frozen review scope

Review branch: `codex/audit-remediation`

Previous reviewed application commit: `93352679621e6e083c2405d4fc698784132a116c`.

Previous reviewed Solidity commit: `0699124bb85b10c89f121e923bf82f38aefeabba`.

Phase-three remediation commit: recorded here after the implementation commit is frozen.

The phase-three report found two unresolved High-severity graduation findings. This delta changes the seed ratio, graduation authorization state machine, deployment script, live-price execution mechanism, fork regressions, CI, and operational documentation. It requires professional retest before Mainnet.

## Solidity scope

- `contracts/src/VOIDBondingCurve.sol`
- `contracts/src/VOIDGraduationExecutor.sol`
- `contracts/src/VOIDUniswapV3Migration.sol`
- `contracts/src/VOIDPositionLocker.sol`
- `contracts/src/VOIDLaunch.sol`
- `contracts/src/VOIDCoin.sol`
- `contracts/src/VOIDTreasuryVesting.sol`
- `contracts/script/Deploy.s.sol`
- all active files under `contracts/test/`
- `contracts/foundry.toml`
- `scripts/security-check.sh`

## External immutable dependencies

- Base chain ID: `8453`
- Official Uniswap v3 NonfungiblePositionManager: `0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1`
- Official Uniswap v3 SwapRouter02: `0x2626664c2603336E57B271c5C0b26F421741e481`
- Canonical Base WETH9 returned by the manager: `0x4200000000000000000000000000000000000006`

## Required retest conclusions

1. Confirm F-01 is closed on a virgin Base pool with seed then direct graduation and no corrective swap.
2. Confirm F-02 is closed by atomic live-state correction plus graduation for curve-side and pool-side price movement.
3. Confirm permissionless execution cannot bypass the Safe seed, reuse a prior target's seed, race a pending target change, redirect migration assets, or alter immutable position custody.
4. Confirm the executor cannot spend curve reserves, retain or steal caller/preexisting assets, select an untrusted router/venue, or graduate at a price other than the curve's live target.
5. Confirm replacement-target recovery remains live and the production Safe's actual fallback handler accepts the locked ERC-721 position on release.
6. Re-run full accounting, full-float redeemability, supply, burn-authority, reentrancy, callback, forced-asset, and rollback invariants over the complete delta.

The production Safe address, threshold, genesis IPFS URI, constructor arguments, deployment calldata, and bytecode reproducibility remain a final separate delta gate. No Mainnet deployment has occurred.

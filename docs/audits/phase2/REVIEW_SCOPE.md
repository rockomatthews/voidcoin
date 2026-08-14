# VOIDCOIN phase-two frozen review scope

Review branch: `codex/audit-remediation`

The final commit hash will be recorded after the owner explicitly approves the proposed curve parameters and the production genesis metadata is published.

## Solidity scope

- `contracts/src/VOIDCoin.sol`
- `contracts/src/VOIDBondingCurve.sol`
- `contracts/src/VOIDTreasuryVesting.sol`
- `contracts/src/VOIDUniswapV3Migration.sol`
- `contracts/src/VOIDPositionLocker.sol`
- `contracts/src/VOIDLaunch.sol`
- `contracts/script/Deploy.s.sol`
- all active files under `contracts/test/`
- `contracts/foundry.toml`
- `scripts/security-check.sh`

## External immutable dependency

- Base chain ID: `8453`
- Official Uniswap v3 NonfungiblePositionManager: `0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1`
- Canonical Base WETH9 returned by the manager: `0x4200000000000000000000000000000000000006`

## Evidence

- Phase-one report and original proof cases: `docs/audits/phase1/`
- Finding disposition: `docs/audits/phase1/REMEDIATION.md`
- Retest questions: `docs/audits/phase1/PHASE2_RETEST_REQUEST.md`
- Migration design: `docs/UNISWAP_MIGRATION.md`
- Proposed economics awaiting explicit owner approval: `docs/CURVE_PARAMETER_PROPOSAL.md`

No Mainnet deployment, buyer funding, Safe execution, or liquidity migration has occurred.

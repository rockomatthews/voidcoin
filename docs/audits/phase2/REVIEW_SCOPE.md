# VOIDCOIN phase-two frozen review scope

Review branch: `codex/audit-remediation`

Previous reviewed commit: `45d6ab4a53d3b4ac8df1db0e432e36c44248cfec`

Frozen remediation commit: `fb5c3eb955ca01931870a8dd1f744609e8e96a6c`.

See `REMEDIATION.md` for the exact delta and remaining blockers.

The phase-two report reviewed the previous commit. Every Solidity, application, economic, and deployment-script change after it is a new delta requiring retest. Production Safe and genesis URI substitution require a final deployment-calldata delta review.

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
- Frozen economics and modeling: `docs/CURVE_PARAMETERS.md`

No Mainnet deployment, buyer funding, Safe execution, or liquidity migration has occurred.

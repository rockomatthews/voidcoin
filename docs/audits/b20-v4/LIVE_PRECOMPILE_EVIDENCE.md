# VOIDCOIN V4 live-precompile evidence

Date: August 20, 2026

This is pre-audit engineering evidence, not an independent audit opinion and not a deployment transaction.

## Environment

- Installer: Base's official `base-foundryup` from `base/base-anvil`
- Binary: `base-forge 1.6.0-v1.1.0`
- Commit: `6130ccf6af0b3399777aee3876486e2ba9ebb38f`
- Execution: local in-process EVM with Base's Rust precompiles enabled
- RPC: none
- Broadcast: none
- Persistent chain-state change: none
- EVM chain ID during the test: `31337`
- Base Mainnet fork/state: none

## Command

```sh
base-forge test --root contracts -vv
```

## Result

```text
Ran 180 tests across the repository
[base-std] LIVE PRECOMPILE mode: exercising base/base's precompiles (conformance check)
Suite result: ok. 171 passed; 0 failed; 9 skipped
```

This includes all 44 `V4Audit` cases, all 8 `V4LiveGate` cases, and all 10 `VOIDB20V4` cases. The passing cases cover
atomic B20/controller creation, exact one-billion supply and cap, adminless role assignment, initial pause, real
supply-reducing contest burns, stale-ID rollback before token movement, metadata mutation, failed metadata rollback,
Safe bypass rejection, and mint rejection.

This run proves behavior against Base's in-process Rust precompiles, but it is not a fork of Base Mainnet and does not
prove current activation or Safe state. A separate read-only RPC preflight at Base block `50240310` returned chain ID
`8453`, `base.b20_asset` activated, and contract code at the production Safe. The Safe reported three owners and a
threshold of two. No transaction was signed or sent.

The auditor must reproduce this independently and record any tool/version or behavior difference.

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

## Command

```sh
base-forge test --root contracts --match-contract VOIDB20V4Test -vv
```

## Result

```text
Ran 10 tests for test/VOIDB20V4.t.sol:VOIDB20V4Test
[base-std] LIVE PRECOMPILE mode: exercising base/base's precompiles (conformance check)
Suite result: ok. 10 passed; 0 failed; 0 skipped
```

The passing cases cover atomic B20/controller creation, exact one-billion supply and cap, adminless role assignment,
initial pause, real supply-reducing contest burns, stale-ID rollback before token movement, metadata mutation, failed
metadata rollback, Safe bypass rejection, and mint rejection.

The auditor must reproduce this independently and record any tool/version or behavior difference.

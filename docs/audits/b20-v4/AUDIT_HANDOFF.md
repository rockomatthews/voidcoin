# VOIDCOIN V4 native B20 — independent audit handoff

Prepared: August 20, 2026

Repository: `https://github.com/rockomatthews/voidcoin`

Branch: `codex/b20-v4`

Frozen production commit: `c7ac786625a92b4c626a5cbfc15816dd2d9a16d1`

## Requested auditor deliverable

Please return a written report that:

1. lists every finding with severity, exploit scenario, affected lines, and recommended remediation;
2. states explicitly whether any unresolved Critical or High finding remains;
3. states whether the frozen production contracts are suitable for Base Mainnet deployment through the supplied script;
4. states whether the token is in fact permanently adminless, exactly capped at one billion units, and initialized with only the intended controller roles;
5. states whether every successful metadata mutation is necessarily bound to a real, final supply-reducing burn;
6. states whether the Safe, deployer, bootstrapper, factory, token holders, and controller owner have any unexpected bypass or privilege;
7. separately reports the result of a no-broadcast simulation against the live Base B20 precompiles; and
8. identifies any assumption that could not be verified.

Please include a frozen commit hash, test commands and results, and any proof-of-concept tests with the report. Do not deploy, broadcast, publish metadata, approve tokens, create an auction, execute a Safe transaction, or unpause the controller as part of this audit.

## Current mainnet state

Nothing in V4 has been deployed or published. Specifically:

- no B20 token, bootstrapper, or V4 controller was deployed;
- no Safe transaction was proposed or executed;
- no token approval or auction was created;
- no V4 metadata was published; and
- no V4 controller was unpaused.

The repository contains older VOID deployments and Zora work. They are not evidence that V4 is live and are out of this review's production scope.

## System intent

V4 creates a Base-native B20 Asset with:

- 18 decimals;
- an exact supply and supply cap of `1_000_000_000 ether`;
- the entire genesis supply minted to the production Safe;
- no `DEFAULT_ADMIN_ROLE` holder;
- no minter, token pauser, unpauser, blocked-burn, seizure, or operator;
- only `VOIDB20SkinController` holding `BURN_ROLE` and `METADATA_ROLE`;
- the controller owned by the production Safe and initially paused; and
- name, ticker, and `contractURI()` changes available only after an eligible token burn and commitment-bound Safe approval.

Deployment is atomic: the bootstrapper predicts the B20 address, deploys its controller against that address, creates and initializes the B20 through the canonical factory, verifies the postconditions, and reverts everything if a postcondition fails.

The later Uniswap launch auction and website cutover are separate operational phases. Auction economics, third-party indexing, and discovery are not security properties of these contracts.

## Critical design tradeoff

The B20 is deliberately created with no default admin. This means the Safe cannot bypass the contest and directly change token metadata, mint, pause, seize, or reassign roles. It also means the controller's `BURN_ROLE` and `METADATA_ROLE` cannot later be revoked or migrated through normal B20 role administration.

The Safe can pause the rename controller, lock a pending slot, approve only commitment-matching metadata, or begin a two-step transfer of controller ownership. It cannot directly exercise the B20 roles. Please assess whether the permanent controller assignment is acceptable and whether any controller behavior could become an unrecoverable token-level risk.

## Production security scope

Review these files at the frozen commit:

| Priority | File | Purpose |
|---|---|---|
| P0 | `contracts/src/VOIDB20SkinController.sol` | Permanent burn and metadata authority; contest state machine |
| P0 | `contracts/src/VOIDB20Bootstrapper.sol` | Atomic B20 creation, exact supply, role setup, postcondition checks |
| P0 | `contracts/script/DeployB20V4.s.sol` | Base Mainnet address, Safe, salt, URI, and broadcast boundary |
| P1 | `contracts/test/VOIDB20V4.t.sol` | Current unit/integration regression suite using Base reference mocks |
| P1 | `contracts/foundry.toml`, `contracts/foundry.lock`, `.gitmodules` | Compiler and dependency resolution |
| P1 | `contracts/lib/base-std` at the pin below | Canonical B20 interfaces, constants, factory encoders, and reference mocks |

Deployment-preparation scripts requiring integration review:

- `scripts/b20-deployment-addresses.mjs`
- `scripts/predict-b20-v4.mjs`
- `scripts/publish-b20-genesis.mjs`
- `scripts/verify-b20-genesis.mjs`
- `scripts/security-check.sh`

Website read-path integration, not contract authority:

- `src/lib/contract.ts`
- `src/lib/token-metadata.ts`
- `src/app/api/state/route.ts`
- `src/components/burn-terminal.tsx`
- `src/components/protocol-stats.tsx`

## External dependency and fixed production identities

- Chain: Base Mainnet, chain ID `8453`
- Production Safe: `0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9`
- Canonical B20 factory: `0xB20f0000000000000000000000000000000000F0`
- Base dependency: `base/base-std` commit `fc13edf179415af235933953fb4537e263c8d1db`
- Solidity compiler: `0.8.30`

The production deploy script hardcodes both chain ID and Safe and obtains the factory from `StdPrecompiles.B20_FACTORY`. The bootstrapper constructor accepts a factory argument for composition and testing; confirm that the production script cannot substitute a different factory.

Primary dependency references:

- `contracts/lib/base-std/docs/B20/Factory.md`
- `contracts/lib/base-std/docs/B20/Asset.md`
- `contracts/lib/base-std/src/interfaces/IB20.sol`
- `contracts/lib/base-std/src/interfaces/IB20Asset.sol`
- `contracts/lib/base-std/src/interfaces/IB20Factory.sol`
- `contracts/lib/base-std/src/lib/B20FactoryLib.sol`
- `contracts/lib/base-std/src/lib/B20Constants.sol`

## Required security confirmations

### Bootstrap and supply

- The predicted token address uses `(ASSET, bootstrapper, salt)` and exactly matches the created address.
- Controller deployment before B20 creation is safe and constructor state cannot be exploited while the predicted token is uninitialized.
- The five ordered initialization calls set the cap, mint exactly one billion tokens to the Safe, set a nonempty contract URI, and grant exactly the two intended roles to the controller.
- `initialAdmin == address(0)` produces a permanently adminless token and the factory retains no persisted privilege.
- No account can mint above the fixed cap, change the cap, grant/revoke roles, pause/unpause the token, block burns, seize balances, or act as B20 Asset operator.
- Constructor postcondition checks cannot be spoofed by the canonical factory/native token, bypassed through malformed return data, or produce a partially initialized deployment.
- Any failure during creation or verification atomically rolls back the controller and token creation.
- The bootstrapper retains no tokens, roles, ownership, approvals, or callable mutation surface.

### Burn accounting and token movement

- `burnForRename` rejects a stale or skipped `expectedBurnId` before token movement or allowance consumption.
- The active slot and accounting state are written before external token calls, with `nonReentrant` protection and full rollback on any revert.
- `safeTransferFrom` moves exactly the submitted amount from the caller to the controller.
- The native B20 `burn` burns exactly the controller's received balance and reduces `totalSupply()` by exactly that amount.
- The post-burn supply assertion is correct under the live B20 implementation, cannot underflow, and detects fee-on-transfer or non-burning behavior.
- The controller retains no contest tokens after a successful burn.
- `contestBurned`, `recordBurn`, `recordBurner`, `currentBurnId`, and `destroyedSupply()` cannot diverge from their documented meanings.
- No holder can burn through this design without intentionally entering the controller contest, because only the controller receives `BURN_ROLE`.

### Contest state machine

- Initial requirement is one million tokens.
- Every takeover satisfies both rules: at least the previous record plus 250,000 and at least a 10% increase, using the greater value and rounding safely.
- The strategic premium cap cannot overflow or lock the contest unexpectedly.
- Commitments bind chain ID, controller, burn ID, burner, burn amount, name, symbol, image hash, metadata URI hash, and salt without collision-prone encoding.
- A commitment cannot be replayed on another chain, controller, burn ID, burner, or amount.
- Only the active burner can replace a commitment; replacement cannot use a stale ID, occur while locked, or occur after expiry.
- Lock, replacement, takeover, approval, and expiry boundary timestamps are internally consistent, including exact equality at `lockedUntil` and slot TTL.
- `expireSlot` cannot erase a new slot through reentrancy or a stale read.
- Expiry clears only the pending proposal; it does not refund or undo a finalized burn.
- Pausing prevents new burns but intentionally does not prevent the owner from resolving an already burned, valid proposal. Confirm this is acceptable.

### Metadata authority

- The Safe cannot call `updateName`, `updateSymbol`, or `updateContractURI` directly.
- `approveRename` can update only the current, unexpired or validly locked, exact commitment.
- Deleting the slot before the three B20 metadata calls is safe under reentrancy and all state/metadata changes roll back atomically if any call fails.
- Name validation allows only 1–15 ASCII alphanumeric/space bytes, no leading/trailing/double spaces.
- Symbol validation allows only 1–10 ASCII alphanumeric bytes.
- Contract URI validation enforces 1–512 bytes; assess whether arbitrary URI schemes or content create a security or ecosystem risk.
- The emitted `SkinChanged` fields faithfully represent the final B20 state.

### Ownership and recovery

- Controller ownership begins at the production Safe.
- `Ownable2Step` prevents accidental one-step ownership transfer, including to an EOA or zero address.
- `renounceOwnership` is permanently disabled.
- A compromised or malicious controller owner cannot bypass the commitment, fabricate a burn, withdraw token balances, mint, or directly use the B20 roles outside controller functions.
- Assess the permanent-role recovery limitation: a paused defective controller remains the immutable B20 role holder because no B20 admin exists.

### Deployment and off-chain preparation

- The deploy script cannot run on a non-Base chain or with a Safe other than the hardcoded production Safe.
- Empty/zero salt and contract URI are rejected.
- Address prediction accounts for the deployer's current nonce when predicting the bootstrapper and for the bootstrapper address when predicting the B20.
- Metadata publication binds the intended predicted B20 address, image, website, name, and ticker, and its verification command fails closed if inputs drift.
- Secrets are neither committed nor emitted into the audit package.
- No command in the documented audit reproduction broadcasts or signs a transaction.

## Live-precompile simulation gate

The existing `VOIDB20V4Test` suite uses Base's official reference precompile mocks. That is necessary but not sufficient. Before a deployment recommendation, reproduce the constructor transaction with no broadcast against a node or simulator that actually implements the live Base B20 factory and native B20 execution.

At minimum, confirm:

1. `getB20Address(ASSET, bootstrapper, salt)` matches the address returned by `createB20`.
2. All five `initCalls` execute in order through the privileged factory initialization window.
3. `isB20` and `isB20Initialized` return true after creation.
4. The controller's role reads work against the native marker-address execution model.
5. Supply, cap, Safe balance, role, owner, paused-state, name, symbol, decimals, and contract URI postconditions match the bootstrapper assertions.
6. A simulated transfer, approval, contest burn, and approval updates metadata and reduces supply exactly once.
7. The simulation makes no persistent chain-state change and produces no broadcast transaction.

If stock Anvil/Forge substitutes the reference mocks, label that result as a mock test rather than live-precompile confirmation. Record the node/client, Base block number, simulator, state overrides if any, and raw call traces.

## Known limitations and out-of-scope items

- No live-precompile deployment simulation has yet been completed.
- Third-party applications can cache or override token metadata. The contract cannot guarantee when Base App, Fomo, DexScreener, BaseScan, wallets, or other indexers show a logo or refreshed name/ticker.
- No Uniswap auction has been created. Auction allocation, valuation, duration, settlement, liquidity migration, LP ownership, approvals, and Safe calldata require a separate economic and operational review.
- The website is a read-only display and external-link surface for trading. It is not an exchange and contains no V4 on-site purchase widget.
- The controller accepts any nonempty URI up to 512 bytes when the commitment matches. Content moderation and availability are operational responsibilities.
- Base protocol upgrades can change native B20 behavior. The review should identify any dependency on semantics not guaranteed by the pinned interfaces and official documentation.
- Historical VOID, V2, and Zora V3 contracts and transactions are out of scope except where the website could accidentally select an old address.

## Frozen source hashes

SHA-256 hashes were computed from `git show c7ac786625a92b4c626a5cbfc15816dd2d9a16d1:<path>`:

```text
6d92b3f0bc1be43ef93314a9caeb92dfe456a60ae2e3fa6fb08c4d5cd187c361  contracts/src/VOIDB20SkinController.sol
cd18e548b4662690a2dde930b7f8b05e51629d295f260cd7a5e983b3ba82863f  contracts/src/VOIDB20Bootstrapper.sol
2f0d731243ffacfe98553c987d9807c4a3038c3d8e736136e683cc3966e3436c  contracts/script/DeployB20V4.s.sol
0fb29280fa81ba484e47680ccfcbe4c0733af94460ae32253dfeb6f3d3b2c727  contracts/test/VOIDB20V4.t.sol
cff046aefc66c60f5291758ae2fbdaba854e28807f7406a566bbc0fdf24072bf  contracts/foundry.toml
e578aff9dcdf5fe7edfb1a3d36aecc3cd09468e9cf02c81d185dbe444239d044  contracts/foundry.lock
525d49c380b2fed57600874781112b51eb972806fd443aa216ac3dc8766aeaee  .gitmodules
35bd0800a1ab311e1a221f82e0821cb91f984401caba95a47c69679b5defbbd5  scripts/b20-deployment-addresses.mjs
210cbef9f25cb02e1640047c5492b1d70d9eb5f911e9c868066ca853bd1ecb93  scripts/predict-b20-v4.mjs
bf555d117e1dccb3cabbee8f63bffd3b1baf4f0f8cd4709d06cbea235b7a4020  scripts/publish-b20-genesis.mjs
69814060ac92ffd9507b68fbbe391e37c8f80900e82c09cd8d10229e5e81c62e  scripts/verify-b20-genesis.mjs
d093beccaa2f34c6ac3fdf385ec49083ef3f73735841597983e2781174171d7b  scripts/security-check.sh
78fe80fb9c9a37b8dce45a7ca5ebb27353321cedb55f617c74f06e6614d6a71a  src/lib/contract.ts
c368b7a77a669203b4589439a2cb2fc2129eb35ecb273b6dfa3bd570cd119b05  src/lib/token-metadata.ts
1a29d722164dea1bb1d212a6edd5107ce5ffd36224533f61ecbb8e066bae354e  src/app/api/state/route.ts
```

## Reproduction

Clone with the pinned submodules and check out the frozen production commit:

```sh
git clone --recurse-submodules https://github.com/rockomatthews/voidcoin.git
cd voidcoin
git checkout c7ac786625a92b4c626a5cbfc15816dd2d9a16d1
git submodule update --init --recursive
npm ci
```

Run formatting, focused B20 tests, the full repository suite, app checks, and static analysis:

```sh
forge fmt --check --root contracts
forge test --root contracts --match-contract VOIDB20V4Test -vv
forge test --root contracts -vv
npm run verify
VOIDCOIN_SOLC_BIN="$(command -v solc)" npm run contracts:security
```

Versions used for the pre-handoff run:

```text
forge 1.7.1 (4072e48705af9d93e3c0f6e29e93b5e9a40caed8)
solc 0.8.30
slither 0.11.6
node v24.15.0
npm 11.12.1
base-std fc13edf179415af235933953fb4537e263c8d1db
forge-std bf647bd6046f2f7da30d0c2bf435e5c76a780c1b
```

Pre-handoff results at the frozen commit:

- focused V4 suite: 10 passed, 0 failed;
- full Foundry run: 119 passed, 0 failed, 9 skipped;
- app tests: 23 passed;
- ESLint: passed;
- Next production build: passed;
- `forge fmt --check`: passed; and
- Slither: 0 findings across all 11 production targets.

Skipped fork tests do not count as live-precompile confirmation. Please rerun everything independently and report any deviation.

## Auditor response template

```text
VOIDCOIN V4 native B20 independent review

Frozen commit reviewed:
Dependency pin verified:
Review dates:
Reviewer:

Critical findings:
High findings:
Medium findings:
Low/informational findings:

Live-precompile simulation environment and Base block:
Live-precompile simulation result:
Mock/unit test result:
Static-analysis result:

Adminless role configuration confirmed: YES / NO
Exact one-billion cap and genesis supply confirmed: YES / NO
Only controller has burn and metadata authority: YES / NO
Safe/deployer/factory/bootstrapper bypass absent: YES / NO
Every approved metadata change requires a finalized supply burn: YES / NO
Controller permanent-role/recovery tradeoff acceptable: YES / NO
Suitable for Base Mainnet deployment through DeployB20V4.s.sol: YES / NO

Unverified assumptions or required pre-flight fixes:
Final written conclusion:
```

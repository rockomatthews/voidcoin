# VOIDCOIN V4 — final independent retest

**Commit retested:** `ac61d3a4a9229883b77f18e38402b090870de20c` (branch `codex/o1-v4`, branch head)
**Production contract freeze:** `c7ac786625a92b4c626a5cbfc15816dd2d9a16d1` — **unchanged**
**Dependency pin:** `base/base-std @ fc13edf179415af235933953fb4537e263c8d1db`
**Retest date:** 20 August 2026
**Reviewer:** independent contract review
**Supersedes:** revision 2. This is the closing report for the V4 engagement.

No private key, seed phrase, or credential was requested or used. Nothing was deployed,
broadcast, published, approved, auctioned, executed through the Safe, or unpaused.

---

## 1. Verdict

**No unresolved Critical or High finding remains — in the contracts or in the launch path.**

Revision 2's two High findings are **both closed at the root**, not worked around:

- **H-1** the legacy Zora fallback is gone. `configuredTokenAddress()` now returns `null`
  when unset or malformed, uses `isAddress`/`getAddress`, and the vitest case that
  *pinned* the bad behaviour has been inverted to assert fail-closed. Three separate API
  paths additionally read `controller.token()` on chain and refuse to serve when it does
  not match the configured token.
- **H-2** the burn-before-moderation workflow is gone. `POST /api/requests` no longer
  returns a commitment at all — it stores a draft with `commitment: null`, status
  `draft`, and tells the user no burn is requested. The commitment is created **only
  after** the moderator pins the final IPFS metadata, so the first and only commitment a
  burner ever executes is URI-bound and openable. `replaceCommitment` is no longer a
  mandatory second leg. The submit button now reads *"SUBMIT FOR MODERATION — NO BURN"*.

**In my assessment `VOIDB20SkinController.sol`, `VOIDB20Bootstrapper.sol`, and
`DeployB20V4.s.sol` are suitable for Base Mainnet deployment through
`DeployB20V4.s.sol`, and the launch path is suitable for public use**, subject to §6.

Four contract-level findings from earlier rounds remain **open and accepted** because the
freeze was deliberately not reopened (§4). They are not blockers; they are permanent
after deployment, and I want that stated plainly rather than buried.

---

## 2. Freeze and hash verification

**Contracts.** `git diff c7ac786 ac61d3a -- contracts/src contracts/script contracts/foundry.toml
contracts/foundry.lock .gitmodules` is **empty**. All three production hashes recomputed
from the retest commit match the frozen values exactly:

```
6d92b3f0bc1be43ef93314a9caeb92dfe456a60ae2e3fa6fb08c4d5cd187c361  VOIDB20SkinController.sol   OK
cd18e548b4662690a2dde930b7f8b05e51629d295f260cd7a5e983b3ba82863f  VOIDB20Bootstrapper.sol     OK
2f0d731243ffacfe98553c987d9807c4a3038c3d8e736136e683cc3966e3436c  DeployB20V4.s.sol           OK
```

**Delivery files.** All **17** hashes published in `REV2_REMEDIATION.md` verified **OK**
against `ac61d3a`. Zero mismatches. This closes **M-10** — the audit package now
publishes hashes for the files that will actually ship, separately from the immutable
contract freeze, which is exactly the fix I asked for.

**Reviewer test files.** `V4Audit.t.sol` and `V4LiveGate.t.sol` were vendored into
`contracts/test/`. I compared them byte-for-byte against my originals: **IDENTICAL**.
They were not softened to make the suite green. I checked because a green suite that
contains the auditor's own tests is only meaningful if those tests are unmodified.

---

## 3. Every revision-2 finding, retested

| ID | Was | Status | How I confirmed |
|---|---|---|---|
| **H-1** | High | **CLOSED** | `contract.ts:185-197` — fallback chain deleted, `isAddress`/`getAddress`, returns `null`; `contract.test.ts` inverted; `state/route.ts:65-68`, `requests/route.ts:58-61`, `admin/.../route.ts:33-36` all read `controller.token()` and 503 on mismatch |
| **H-2** | High | **CLOSED** | `requests/route.ts` — `createCommitment`/`zeroHash` imports removed, `commitment: null`, `status: "draft"`; `admin/.../route.ts:39-70` pins metadata **then** computes the URI-bound commitment and sets `awaiting_burn`; migration `0001_premoderate_before_burn.sql` makes both commitment columns nullable |
| M-3 | Medium | **CLOSED** | Verifier now has two phases. Predeploy re-derives from `b20PredictionFromEnvironment()` and rejects stale token/nonce/salt. Postdeploy (`--token`/`--controller`) reads Base Mainnet and asserts `contractURI === receipt.metadataURI` and `controller.token() === token` |
| M-4 | Medium | **CLOSED** | `GET /api/requests` now requires a valid wallet **and** an explicit UUID list (≤10). Enumeration from a published `recordBurner` address no longer returns anything |
| M-5 | Medium | **MOSTLY CLOSED** | `npm run verify` now runs `b20:surface:test`; the runbook lists both gates. The network-dependent `b20:surface:verify` correctly stays out of `verify` |
| M-6 | Medium | **CLOSED** | `burn-terminal.tsx` checks `receipt.status !== "success"` on both the approval and the execution legs; `confirm/route.ts` adds status/commitment/mode preconditions |
| M-7 | Medium | **OPEN, impact reduced** | Client still submits `authorization.commitment` verbatim; salt still never leaves the server (0 occurrences of `keccak256`/`encodeAbiParameters` in the component). But the commitment is now post-moderation, URI-bound, openable, and the exact name/ticker appear on the button |
| M-8 | Medium | **CLOSED, better than asked** | `links` is now the full six-route object **and** `market_links` carries the six typed entries — both shapes, as recommended. Evidence captured in `docs/research/basecat-b20-metadata.json` |
| M-9 | Medium | **CLOSED** | `assertBytesMatchCid` rehashes gateway bytes and compares against raw CIDv1 plus UnixFS candidates for both `rawLeaves` modes, version-aware |
| M-10 | Medium | **CLOSED** | See §2 |
| L-1 | Low | **CLOSED** | Handoff now reads `0xB20f000000000000000000000000000000000000` |
| L-9 | Low | **OPEN** | `state/route.ts` still returns raw `error.message` on the 502 path |
| L-10 | Low | **MOSTLY CLOSED** | Token and controller resolvers use `isAddress`. `configuredV2BuyRouterAddress` (`:198`) and `configuredCurveAddress` (`:215`) still use prefix+length, and the latter still defaults to the V1 curve — both legacy, dormant |
| L-11 | Low | **PARTLY CLOSED** | Approval receipt status is now checked. A pre-existing larger allowance is still reused and never reset to zero |
| L-12 | Low | **CLOSED** | `CID.parse` plus `/^ipfs:\/\/[^/]+$/` |
| L-13 | Low | **CLOSED** | `redirect: "manual"`, ≤2 hops, HTTPS-only, same-origin, `content-length` pre-check, streaming byte cap (256KiB metadata / 5MiB image) |
| L-14 | Low | **CLOSED** | description ≥40 chars, decimals 18, `images[]`/`icons[]` bound to `image`, `properties.contractAddress`, `properties.standard`, interop flags, all six routes in both places |
| L-15 | Low | **CLOSED** | `sharp` and the three IPFS libraries are all in `devDependencies`; `npm audit --omit=dev` → **0 vulnerabilities**, reproduced |
| I-2 | Info | **CLOSED** | `token_standard` is now `"B20"`, matching `standard` |

---

## 4. Findings that remain open — and are now permanent

The freeze was deliberately not reopened, which I think was the right call: the contracts
were clean and reopening a freeze to chase Mediums invites new risk. But these four
become **unfixable the moment you deploy**, so I am restating them once, plainly.

- **M-1 — `lockRenameSlot(burnId)` does not pin the commitment.** The active burner can
  front-run the Safe's lock with `replaceCommitment` and freeze the wrong commitment for
  six hours, repeatable for gas across the 72-hour TTL. Self-funded griefing (the attacker
  already burned ≥1,000,000 VOID), availability only. `testF1` reproduces it.
  **Operational mitigation:** have the Safe read `activeSlot().commitment` immediately
  before signing the lock and abort on any change. The admin route already knows the
  intended commitment.
- **M-2 — renaming rotates the EIP-712 domain, so renaming *back* to a prior name
  resurrects an unused, unexpired permit signature.** `testF2` reproduces it end to end
  against the live precompiles: a whale's max-deadline permit dies on rename and revives
  on rename-back, and the attacker moves the funds. **Operational mitigation:** maintain a
  list of every name the token has ever carried, including "VOIDCOIN", and make it a
  hard Safe rule to reject any proposal reusing one. This is now a *procedural* control
  where a `mapping(bytes32 => bool) nameUsed` would have been a structural one.
- **L-3 — bootstrap postconditions omit decimals, contract URI, name, symbol, and
  BURN/METADATA role exclusivity.** Unreachable with the canonical factory; `testF3`
  shows a factory honouring only the checked invariants passes. Defence in depth only.
- **L-7 — `updateExtraMetadata` is permanently unreachable.** The controller holds
  `METADATA_ROLE` exclusively and exposes no path to it, so the ERC-7572 extra-metadata
  key/value surface can never be used on this token. Given how much work went into
  discoverability this round, worth a last look before the roles become irrevocable.

Also still open, non-contract and non-blocking: **M-7** (client cannot recompute the
commitment), **L-2** (the contest ends after 44 qualifying burns, stranding
80,141,413.88 VOID — by design), **L-4**, **L-5**, **L-6** (no `forge` version pinned
anywhere machine-readable — I confirmed no `.foundry-version` or equivalent was added),
**L-8**, **L-9**, and the residual halves of **L-10** and **L-11**.

---

## 5. New findings in this retest

I re-ran my own independent harness against the rewritten verifier — **30 scenarios,
24 blocked, 6 passed, 1 deviation** — deliberately not reusing your
`scripts/surface-readiness-harness.mjs`, since the point of a retest is to probe
independently. Part 1 re-ran every revision-2 gap; **all ten are now blocked**. Part 2
probed the new code with cases I had not previously raised.

Three new items, all Low. None blocks launch.

**N-1 (Low) — the local `receipt.metadata` is schema-validated but not byte-bound to the
pinned CID.** Scenario N17: the receipt's local copy carries a description one sentence
longer than the pinned document; both copies individually satisfy `assertMetadata`, the
pinned bytes hash correctly, and the verifier **passes**. A control probe (N19, mutating
only the receipt copy to `symbol: "WRONG"`) does block, so the copy *is* validated — it
is just never compared to what was actually pinned. What goes on chain is the CID, and
the CID's content is now fully verified, so this is an audit-trail consistency gap rather
than a security hole. But `verify-b20-genesis.mjs` reads `receipt.metadata.*` for its own
assertions, and a human reading the receipt takes it as the record of what was published.
**Fix:** one line — `assertBytesMatchCid(Buffer.from(JSON.stringify(receipt.metadata)),
metadataCid, "receipt.metadata")`, or compare the parsed gateway document to
`receipt.metadata` directly.

**N-2 (Low/Informational) — `links` and `market_links` are compared with
`JSON.stringify` deep equality, so the schema is closed to additions and sensitive to key
order.** Scenario N15: adding a harmless `links.telegram` is **rejected**. Scenario N16:
the identical six values in a different key order are **rejected**. Failing closed is the
safe direction and I would not change the strictness — but be aware that (a) you cannot
add a social link later without editing the verifier, and (b) any pipeline that
re-serialises the JSON with different key ordering will fail the gate for a reason that
reads as a content error. Consider comparing per-key rather than by serialised string.

**N-3 (Low) — the pointer to a pending proposal lives only in `localStorage`.**
`burn-terminal.tsx` sends `?ids=` from `window.localStorage["voidcoin-request-ids"]`. A
user who submits a draft on desktop and returns on mobile, or who clears site data, sees
no execute button — the proposal is not lost (the moderator has it) and no tokens are at
risk (nothing has burned), but they have no self-service path back to it. This is the
cost of the M-4 fix and it is the right trade; just make sure support has a way to
re-surface a request id.

### New probes the hardened verifier passed cleanly

Worth recording, because these are the cases where a CID check is usually got wrong:

- **N1** CIDv0 (`Qm…`, dag-pb) metadata with matching bytes → accepted.
- **N2** UnixFS CIDv1 with `rawLeaves: false` → accepted.
- **N3** a multi-block UnixFS image (93,645 bytes, spanning chunks) → accepted.
- **N4/N5/N6** cross-origin redirect, `http://` downgrade, and a four-hop same-origin
  chain → all blocked.
- **N7** a body far larger than a *falsely declared* `content-length: 1024` → blocked by
  the streaming cap, not the header.
- **N8** correct bytes served as `text/plain` → blocked.
- **N9/N10** real JPEG as `image/jpeg` and the same JPEG mislabelled `image/png` → both
  blocked at the byte level.
- **N11** a **solid opaque single-colour** logo → blocked by the entropy floor. This is
  stronger than the transparent-blank case I originally raised, and I had not asked for it.
- **N12/N13** exactly 512×512 accepted, 511×511 rejected — the documented boundary is
  inclusive and exact.
- **N14** one honest gateway and one serving a valid document for a *different* token →
  blocked at the CID check before the schema check even matters.
- **N18** verification against a different expected address → blocked, which is the
  mechanism the postdeploy phase relies on.

---

## 6. Verification results

Every figure in `REV2_REMEDIATION.md` reproduced. Toolchain: forge 1.7.1
(`4072e48705af9d93e3c0f6e29e93b5e9a40caed8`), base-forge 1.6.0-dev from base-anvil
`9df661bc39c6fb96ef28bfd5ff5d345931f133d3`, solc 0.8.30, Slither 0.11.6, node 22.22.2.

| Check | Claimed | Reproduced | Match |
|---|---|---|---|
| `npm run verify` | passes | **exit 0** | ✅ |
| — app tests | 24 | **24 passed (6 files)** | ✅ |
| — client surface harness | 39 scenarios, 0 deviations | **39 scenarios, 0 deviations** | ✅ |
| — ESLint / Next build | pass | pass | ✅ |
| `forge fmt --check --root contracts` | passes | **exit 0** | ✅ |
| Stock Forge (excl. live-gate suite) | 163 / 0 / 9 | **163 passed, 0 failed, 9 skipped** | ✅ |
| `V4Audit.t.sol` | 44 / 44 | **44 passed, 0 failed** | ✅ |
| Base patched Forge, full repo | 171 / 0 / 9 | **171 passed, 0 failed, 9 skipped** | ✅ |
| `V4LiveGate.t.sol` under live precompiles | 8 / 8 | **8 passed, 0 failed** | ✅ |
| Slither, 11 targets | 0 findings | **0 findings across 11 targets** | ✅ |
| `npm audit --omit=dev` | 0 production vulnerabilities | **found 0 vulnerabilities** | ✅ |
| **Reviewer's own retest harness** | — | **30 scenarios, 1 deviation (N-1)** | new |

**The one claim I could not corroborate** is the read-only Base preflight: block
`50240310`, chain ID 8453, `base.b20_asset` activated, production Safe with code, three
owners, threshold two. Every public Base RPC endpoint remains blocked from this
environment. Your `LIVE_PRECOMPILE_EVIDENCE.md` now states the limitation correctly and
in the right place — that the patched-Forge run uses chain ID 31337, is not a fork, and
proves precompile semantics rather than chain state. I agree with that framing. **Repeat
the preflight immediately before broadcast** and keep the raw output; a two-month-old
activation check is not a launch-day activation check.

---

## 7. Remaining launch gates

Your list in `REV2_REMEDIATION.md` is correct and I would not add much. Sequenced, with
the two things I would insist on:

1. **Rehearse the full metadata publication and surface verifier on throwaway content.**
   Both phases: predeploy (needs `DEPLOYER_ADDRESS`, `BASE_MAINNET_RPC_URL`,
   `VOID_B20_SALT`) and, after a testnet or dummy deployment, the `--token`/`--controller`
   phase. The predeploy phase now *requires* an RPC, so it can no longer be run offline —
   confirm the operator machine has one before launch day.
2. **Re-run the Base preflight** (activation, Safe, chain ID) and `npm run b20:verify` in
   the **same operator step** as the broadcast, not hours before.
3. Deploy only under separate authorisation. Rebuild the bytecode from `c7ac786` at
   broadcast time and compare.
4. Run the postdeployment chain-bound verifier against the real addresses.
5. Apply `0001_premoderate_before_burn.sql` and deploy the website. Verify `/api/state`
   returns 503 rather than serving a wrong token if the env is incomplete — that is the
   H-1 fix doing its job.
6. Create and settle the separately approved Uniswap auction. **Out of scope for this
   engagement** — auction economics, allocation, settlement, LP ownership, and the Safe
   calldata all need their own review.
7. Verify third-party displays, then smoke-test moderation end to end with a real draft.
8. Unpause the controller as a separate Safe action. **Before you do:** commit the M-2
   used-name list and the M-1 lock-then-verify procedure to writing, because after that
   point neither can be fixed in code.

---

## 8. Assumptions I could not verify

1. **Base Mainnet's deployed precompiles match the builds tested.** Two independent
   base-forge builds pinning two different `base/base` revisions agree, which is strong —
   but both are builds of the repository, not reads of the chain.
2. **`base.b20_asset` activation and the production Safe's configuration.** Your
   preflight reports both; no Base RPC was reachable here.
3. **The Basecat/PAMPU evidence.** `docs/research/basecat-b20-metadata.json` is real,
   checkable evidence with a CID, gateway URL and response SHA-256 — a large improvement
   on the unsourced claim. But it is one observed token's document, captured by you, and
   `ipfs.io` is blocked here so I could not re-fetch it. It demonstrates the shape exists
   in the wild; it does not establish a schema.
4. **The o1 factory analysis** in `docs/O1_LAUNCH_COMPATIBILITY.md`. Sourcify and
   `docs.o1.exchange` were unreachable.
5. **The live IPFS gateways.** `gateway.pinata.cloud` and `ipfs.io` are blocked here; §5
   used a faithful in-process stub.
6. **Deployer nonce discipline** between prediction and broadcast.
7. **IPFS pinning durability**, and whether third-party indexers consume the ERC-7572
   `contractURI` and how quickly they refresh after a rename.

---

## 9. Closing statement

```text
VOIDCOIN V4 native B20 — final independent retest

Commit retested:         ac61d3a4a9229883b77f18e38402b090870de20c (codex/o1-v4 head)
Contract freeze:         c7ac786625a92b4c626a5cbfc15816dd2d9a16d1 — UNCHANGED
                         3/3 production contract hashes verified
                         17/17 delivery hashes verified
                         reviewer test files vendored byte-identical
Dependency pin verified: base/base-std @ fc13edf179415af235933953fb4537e263c8d1db
Retest date:             20 August 2026

Unresolved Critical findings:  0
Unresolved High findings:      0   (H-1 and H-2 both CLOSED at the root)
Open Medium findings:          1   (M-7, client cannot recompute its own commitment;
                                    impact materially reduced by the H-2 fix)
Accepted-and-permanent:        M-1, M-2, L-3, L-7 — contract findings the freeze
                                    deliberately did not reopen. Unfixable after
                                    deployment. Operational mitigations in section 4.
Open Low/informational:        L-2, L-4, L-5, L-6, L-8, L-9, residual L-10/L-11,
                                    plus new N-1, N-2, N-3.

Live-precompile result:  171 passed, 0 failed, 9 skipped, LIVE PRECOMPILE banner.
                         V4Audit 44/44, V4LiveGate 8/8, VOIDB20V4 10/10.
                         base-forge 1.6.0-dev from base-anvil 9df661bc39c6fb96,
                         pinning base/base cea79451170a576c. chainid 31337, no fork.
Mock/unit result:        163 passed, 0 failed, 9 skipped (stock forge 1.7.1).
Surface gate:            client harness 39/39, 0 deviations (reproduced).
                         Reviewer's independent harness 30 scenarios, 1 deviation (N-1).
Static analysis:         Slither 0 findings across 11 targets.
Production dependencies: npm audit --omit=dev — 0 vulnerabilities.

Adminless role configuration confirmed:                              YES
Exact one-billion cap and genesis supply confirmed:                  YES
Only controller has burn and metadata authority:                     YES
Safe/deployer/factory/bootstrapper bypass absent:                    YES
Every approved metadata change requires a finalized supply burn:     YES
Controller permanent-role/recovery tradeoff acceptable:              YES
Suitable for Base Mainnet deployment through DeployB20V4.s.sol:      YES
Launch path suitable for public use:                                 YES, subject to
                                                                     section 7

Final written conclusion:
    No unresolved Critical or High finding remains anywhere in scope. The three
    production contracts are byte-identical to the audited freeze and behave
    correctly against base/base's real Rust B20 precompiles. Both revision-2 High
    findings were fixed at their root rather than mitigated: the legacy Zora
    address fallback is deleted and the site now fails closed with an on-chain
    controller/token binding check, and the burn-before-moderation workflow is
    replaced by pin-metadata-first so that the only commitment a burner ever
    executes is URI-bound and openable. The metadata gateway verifier has been
    rewritten into a genuine two-phase gate that reads Base Mainnet after
    deployment and verifies that gateway bytes hash to the advertised CID; my
    independent 30-scenario retest found every previously reported gap closed and
    one new Low. The remaining contract-level findings — M-1, M-2, L-3, L-7 — were
    accepted rather than fixed and become permanent on deployment; the operational
    mitigations in section 4 should be committed to writing before the controller
    is unpaused. I could not corroborate the read-only Base preflight, as no Base
    RPC was reachable from this environment; repeat it immediately before broadcast.
```

---

## 10. Reproduction

```sh
git clone --recurse-submodules https://github.com/rockomatthews/voidcoin.git
cd voidcoin && git checkout ac61d3a4a9229883b77f18e38402b090870de20c
git submodule update --init --recursive && npm ci

git diff --stat c7ac786625a92b4c626a5cbfc15816dd2d9a16d1 HEAD -- \
  contracts/src contracts/script contracts/foundry.toml contracts/foundry.lock .gitmodules   # must be empty

forge fmt --check --root contracts
forge test --root contracts --no-match-contract VOIDCOINV4LiveGateTest
forge test --root contracts --match-contract VOIDCOINV4AuditTest
npm run verify
npm audit --omit=dev
VOIDCOIN_SOLC_BIN="$(command -v solc)" npm run contracts:security

base-forge test --root contracts                       # or FOUNDRY_BASE=true on a base-anvil build
base-forge test --root contracts --match-contract VOIDCOINV4LiveGateTest -vv

cp /path/to/auditor_surface_retest.mjs scripts/
node scripts/auditor-surface-retest.mjs                # reviewer's independent harness
```

`testGate0` remains the guard: it passes only when base-std prints `LIVE PRECOMPILE mode`
and fails with an explicit message under stock forge. A gate run reporting a pass without
that banner is invalid.

No command above broadcasts, signs, requires a private key, or contacts Base Mainnet.

# VOIDCOIN — Phase One Independent Security Review

**Target:** `github.com/rockomatthews/voidcoin`
**Reviewed revision:** `18e79a24576fe2a028bf17706342989e96fec0d8` (*"Make npm lock portable across CI platforms"*, 2026-08-13)
**Intended chain:** Base Mainnet (chain ID 8453)
**Deployment status at review time:** not deployed
**Review date:** 2026-08-13
**Review type:** manual source review with executable proofs of concept, plus reproduction of the project's own automated baseline

---

## 0. Important statement about this review

Read this section before the findings.

This review was produced by Claude, an AI system, working directly against the frozen commit. It is a real technical review — every finding below is reproduced by an executable Foundry test that is delivered with this report — but it is **not** a commercial audit engagement and it must not be presented as one.

Specifically:

- **This is not a substitute for a named audit firm.** No entity signs off on this work, no professional indemnity or liability attaches to it, and no reviewer's reputation is staked on it. Base ecosystem partners, listing venues, and prospective holders who ask for "an audit" are asking for something this document is not.
- **I cannot honestly confirm the credential you asked for.** Your request item 5 asks for confirmation of prior experience reviewing EVM bonding curves, liquidity migrations, and Base deployments. I have no professional history, no client list, and no track record to point to. What I can offer is the work itself: the findings are specific, they come with failing-by-construction test cases, and you can verify every one of them in a few minutes with the commands in Section 8. Judge it on that, not on a claimed résumé.
- **I cannot give you a binding quote or a contractual timeline.** Section 9 contains realistic market ranges for what a firm will charge and how long they will take, so you can budget and plan. Those are informational estimates, not a bid, and I am not a party you can engage.
- **Retesting after fixes (your item 3) is something I can do**, in the same form as this document, whenever you have a fix branch ready.

The correct way to use this report is as a pre-audit hardening pass: fix what is below, then hand a cleaner codebase to a paid firm. That sequencing will save you money, because firms price partly on how much noise they have to wade through, and it will make their engagement more valuable because they will be spending their hours on things I missed rather than on things I found.

---

## 1. Executive summary

The contracts are small, readable, non-upgradeable, and free of the categories of bug that automated tooling finds. I independently reproduced the project's baseline: **17/17 Foundry tests pass**, and **Slither 0.11.6 with solc 0.8.30 analyses 22 contracts with 101 detectors and reports zero findings**. That baseline is accurate as stated in the brief.

It is also, on its own, close to meaningless as a safety signal. Every issue in this report is semantic or economic. Not one of them is the kind of thing Slither is built to find, and the reason the static analysis is clean is that the code does exactly what it was written to do. The problem is what it was written to do.

**The protocol is not ready for Base Mainnet.** Your own position — that phase two is required before deployment — is correct, and I would go further: the single largest risk in this system is structural rather than parametric, and it will not be resolved by freezing the migration adapter's address. It will only be resolved by changing how the curve hands off funds.

### Findings

| ID | Severity | Title |
|---|---|---|
| C-01 | **Critical** | Graduation is an irreversible one-way transfer of 100% of protocol funds to an immutable address, with no timeout, no rescue, no re-targeting, and sells disabled the moment the threshold latches |
| H-01 | **High** | Forced ETH latches `graduationReady` early, closing the market and trapping every holder |
| H-02 | **High** | Zero-fee, no-deadline curve makes sandwiching unconditionally profitable; the project's own tests and integration pattern pass `minimumTokensOut = 0` |
| H-03 | **High** | The 100,000,000 VOID treasury allocation can be sold back into the buyer-funded curve, extracting buyer ETH; vesting is linear from t=0 with no cliff |
| M-01 | Medium | Sell-side exit failure: large holders cannot exit, `sell` reverts rather than partially filling, and `quoteSell` silently returns `0` |
| M-02 | Medium | `metadataURI` is never bound to the commitment; the Safe can substitute arbitrary content after the burner has paid |
| M-03 | Medium | If the Safe never calls `acceptOwnership()`, the token's owner is a contract that provably cannot ever act, and renaming is permanently stuck paused |
| M-04 | Medium | A superseding burn — or a free `replaceCommitment` — reverts the Safe's queued `approveRename`; multisig latency makes the window large |
| M-05 | Medium | No slot expiry or owner-side cancel; `openedAt` is written and never read |
| L-01 | Low | `VOIDLaunch` does not validate that `migrationTarget` has code; `graduate()` then reverts with empty data rather than `MigrationFailed` |
| L-02 | Low | Rounding favours the trader on both sides; the curve leaks ETH and `balance ≥ net deposits` is false |
| L-03 | Low | `evm_version` is not pinned in `foundry.toml`; reviewed bytecode is not reproducible across Foundry versions |
| L-04 | Low | The rename mechanism silently self-terminates after 44 renames |
| L-05 | Low | The `VestingWallet` is renounceable and transferable by the Safe |
| L-06 | Low | No deadline parameter on `buy` / `sell` |
| I-01 … I-07 | Informational | Dead code, unused state, test-coverage gap, disclosure accuracy (Section 6) |

### The one-paragraph version

Buyers put real ETH into a curve that promises they can sell back out. The moment the ETH balance touches the threshold, that promise is revoked — `sell()` reverts — and every holder's entire position depends on one Safe transaction calling one immutable address that has not been written yet. If that address is broken, all funds freeze forever. If the Safe renounces ownership, all funds freeze forever. If that address is malicious, all funds are swept and every post-condition in `graduate()` still passes. There is no timeout, no rescue function, no way to reopen trading, and no way to point at a different adapter. Three lines of Solidity would not fix this; it needs a different graduation design.

---

## 2. Scope

### In scope and reviewed

| File | Lines | Reviewed |
|---|---|---|
| `contracts/src/VOIDCoin.sol` | 214 | Yes, line by line |
| `contracts/src/VOIDBondingCurve.sol` | 139 | Yes, line by line |
| `contracts/src/VOIDLaunch.sol` | 43 | Yes, line by line |
| `contracts/script/Deploy.s.sol` | 43 | Yes |
| `contracts/test/VOIDCoin.t.sol` | 211 | Yes, reviewed as coverage evidence |
| `contracts/test/VOIDLaunch.t.sol` | 107 | Yes, reviewed as coverage evidence |
| `contracts/foundry.toml` | — | Yes |
| `docs/SECURITY.md`, `docs/LAUNCH_GATES.md` | — | Read for stated intent |

Dependency: OpenZeppelin Contracts `5.6.1` as resolved from `package-lock.json`. `ERC20`, `Ownable`, `Ownable2Step`, `ReentrancyGuard`, `SafeERC20`, `Address`, and `VestingWallet` were treated as trusted and were **not** audited; their *usage* was reviewed.

### Explicitly excluded from this review

Per your request, here is exactly what I did **not** review, stated plainly:

1. **The migration target.** It does not exist at this commit. Everything that happens after `migrate()` is called — the Uniswap or other venue integration, pool creation, fee tier, price range, tick alignment, LP token or position NFT custody, the lock arrangement, slippage on the initial mint, and the recovery recipient — is entirely unreviewed. This is the largest single concentration of value in the protocol and it is outside the scope of this document.
2. **All economic parameters.** `virtualEthReserve` and `graduationThreshold` are unfrozen. Several findings below (notably H-02 and M-01) change in severity depending on what you choose. I used `virtualEthReserve = 1 ether` and `graduationThreshold = 10 ether` in the proofs of concept because those are the shapes your own tests use; different values change the magnitudes, not the existence, of the issues.
3. **The production Safe.** Address, signer set, threshold, signer key custody, and transaction-review process are unreviewed. Every finding involving the Safe assumes an honest, competent, uncompromised Safe. If that assumption fails, the Safe can substitute arbitrary token metadata (M-02) and, once an adapter exists, direct all protocol funds (C-01).
4. **Deployment calldata and the deployment operation itself.** Constructor arguments, the broadcast transaction, source verification, and the post-deployment ownership acceptance sequence are unreviewed.
5. **The Next.js application** under `src/app/api` and `src/lib`. Commitment construction, calldata generation, receipt validation, Safe approval preparation, event indexing, image moderation, webhook handling, and authentication were not reviewed. You offered this as an optional separate scope and it remains unexercised. Note that M-02 and M-04 both have significant off-chain components, so an application review would materially reduce their real-world impact.
6. **Bytecode reproducibility.** I compiled from source but did not perform a deterministic build comparison against any deployed artifact, because nothing is deployed. See L-03 — the current configuration will not reproduce deterministically across Foundry versions.
7. **Non-technical risk.** Securities, trademark (the "VOIDCOIN"/"VOID" name and symbol collision), consumer protection, tax, sanctions, and money transmission. Your `docs/SECURITY.md` already flags this and is right to.
8. **Base sequencer and L1 assumptions.** I did not review behaviour under sequencer downtime, forced-inclusion via L1, or reorg conditions. Note that Base's single-sequencer ordering means H-02 (sandwiching) currently requires sequencer-privileged or first-in-queue positioning rather than a public mempool auction; that is a mitigation of degree, not of kind, and it degrades if Base's ordering policy changes.

---

## 3. Verification of the stated baseline

I reproduced the brief's claims exactly.

```
forge test --root contracts
  → 17 tests passed, 0 failed (4 suites)
  → invariantSupplyCannotIncrease: 256 runs, 128,000 calls
  → invariantUnauthorizedCallsCannotChangeMetadata: 256 runs, 128,000 calls

slither contracts/src/VOIDLaunch.sol --compile-force-framework solc \
  --solc-solcs-bin <solc-0.8.30> --exclude timestamp
  → contracts/src/VOIDLaunch.sol analyzed (22 contracts with 101 detectors), 0 result(s) found
```

Both claims are accurate. Two comments on how they should be read.

**The Slither result is expected, not reassuring.** All 101 detectors look for syntactic and dataflow patterns: unchecked return values, reentrancy shapes, uninitialised storage, shadowing, weak PRNG. The code has none of those. Every finding in this report is about what the code correctly does. A clean Slither run on a 400-line codebase is the floor, not evidence of safety, and I would push back on `docs/LAUNCH_GATES.md` gate 1 treating "zero Slither findings" as a meaningful gate.

**The "fuzz and invariant suites" claim overstates coverage of the riskiest contract.** There are two invariant tests. Both target `VOIDCoin` metadata and supply, driven by a handler that only calls two functions which are *expected* to fail. Zero of the 128,000 calls reverted, which means the handler never once did anything interesting. There is **one** fuzz test, on the burn escalation. `VOIDBondingCurve` — the contract that holds all the real money — has **no fuzz tests and no invariant tests at all**, only five happy-path unit tests. See I-04.

---

## 4. Critical and High findings

---

### C-01 — Critical — Graduation is an irreversible one-way transfer of all protocol funds to an immutable address, with no recovery path

**Files:** `contracts/src/VOIDBondingCurve.sol` L20, L86, L103, L119–131; `contracts/src/VOIDLaunch.sol` L29–34
**PoC:** `testC01_BrokenAdapterPermanentlyFreezesAllBuyerEth`, `testC01_RenounceOwnershipPermanentlyFreezesAllBuyerEth`, `testC01_MaliciousAdapterPassesEveryPostCondition`

#### The structure

Four design decisions combine into a single point of total failure:

```solidity
address public immutable migrationTarget;                    // L20  — can never be changed

function buy(...)  { if (graduationReady || graduated) revert CurveClosed(); ... }   // L86
function sell(...) { if (graduationReady || graduated) revert CurveClosed(); ... }   // L103

function graduate() external onlyOwner nonReentrant {         // L119 — the only exit
    if (!graduationReady || graduated) revert GraduationNotReady();
    graduated = true;
    uint256 tokens = tokenReserve();
    uint256 eth = address(this).balance;
    token.forceApprove(migrationTarget, tokens);
    try IVOIDMigrationTarget(migrationTarget).migrate{value: eth}(address(token), tokens) {
        if (tokenReserve() != 0 || address(this).balance != 0) revert MigrationFailed();
    } catch {
        revert MigrationFailed();
    }
    emit Graduated(migrationTarget, eth, tokens);
}

function _checkGraduation() private {                          // L133 — one-way latch
    if (address(this).balance >= graduationThreshold) {
        graduationReady = true;
        emit GraduationReady(address(this).balance, tokenReserve());
    }
}
```

`graduationReady` is a one-way latch with no reset. Once set, both `buy` and `sell` revert forever. The contract has exactly one function that can move value out, it is `onlyOwner`, and it sends everything to a hardcoded address. There is no timeout, no emergency withdrawal, no partial exit, no setter for `migrationTarget`, and no circuit breaker.

#### Failure mode 1 — a non-functional adapter freezes everything permanently

The adapter reverts (bug, paused dependency, upgraded-away proxy, a Uniswap pool that cannot be initialised at the resulting price, an out-of-gas condition on a large mint). `graduate()` reverts. Trading is already closed. Nothing else can be called.

```
C-01 permanently frozen ETH (wei): 12000000000000000000     // 12 ETH of real buyer money
C-01 permanently frozen VOID:      69230769230769230769230768
```

The PoC advances time by 3,650 days and retries. Still reverts. This is unrecoverable — not "recoverable by governance," not "recoverable by upgrade," but permanently gone, because the contract is non-upgradeable by design and `migrationTarget` is `immutable`.

#### Failure mode 2 — `renounceOwnership()` freezes everything permanently

`VOIDBondingCurve` inherits plain `Ownable`, not `Ownable2Step`, and does not override `renounceOwnership()`. It is live, unguarded, and one Safe transaction away.

```solidity
vm.prank(safe);
curve.renounceOwnership();      // succeeds
assertEq(curve.owner(), address(0));
// graduate() is now uncallable by anyone. 10 ETH stranded forever.
```

Note the asymmetry: you correctly used `Ownable2Step` on `VOIDCoin`, where a mistaken ownership transfer costs you the ability to rename the token, and plain `Ownable` on `VOIDBondingCurve`, where a mistaken ownership transfer costs every buyer everything. That is backwards.

#### Failure mode 3 — a malicious adapter passes every post-condition

The two post-conditions are `tokenReserve() == 0` and `address(this).balance == 0`. An adapter that simply forwards everything to an attacker satisfies both:

```solidity
function migrate(address token, uint256 tokenAmount) external payable {
    IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
    IERC20(token).transfer(thief, tokenAmount);
    (bool ok,) = thief.call{value: msg.value}("");
    require(ok);
}
```

```
C-01 rug ETH taken (wei): 10000000000000000000   // graduate() returns successfully
```

The post-conditions verify that the funds *left*. They verify nothing about where they went, that a pool was created, that liquidity was actually minted, or that the LP position is held by anyone in particular. A compromised Safe, a mis-set constructor argument, or a compromised adapter deployment is a complete loss with no on-chain tripwire.

#### Why this is Critical and not High

Impact is 100% of protocol funds. Likelihood is not negligible: the adapter does not exist yet, is the most complex unwritten component, integrates with an external AMM, and will be deployed once with an address that can never be corrected. `docs/SECURITY.md` already says "a faulty migration adapter can strand or lose funds" — that is the right diagnosis, and the code's response to it is currently nothing.

#### Remediation

This needs a design change, not a patch. In rough priority order:

1. **Make graduation reversible until it succeeds.** If `migrate()` fails, the curve should return to the open state so holders can exit, rather than staying latched shut:
   ```solidity
   function abortGraduation() external onlyOwner {
       if (graduated) revert AlreadyGraduated();
       graduationReady = false;
       emit GraduationAborted();
   }
   ```
   Pair this with raising the threshold or requiring a fresh `_checkGraduation`, so aborting does not create a griefing loop.

2. **Add a timelocked emergency exit.** If `graduationReady` has been latched for more than N days without a successful `graduate()`, allow either pro-rata redemption by holders or an owner-triggered reopen. Buyers should never be in a position where their capital's fate is a single transaction that may never be sent.

3. **Make `migrationTarget` settable by the owner while `graduated == false`, behind a timelock and an event.** The immutability here buys you a trust property you are not actually delivering — the owner already controls whether and when funds move — while costing you the ability to fix a broken adapter. If you keep it immutable, you must accept that a bad adapter is a total loss, and you must say so prominently to buyers.

4. **Disable renunciation on both contracts:**
   ```solidity
   function renounceOwnership() public pure override {
       revert RenouncingDisabled();
   }
   ```
   Apply to `VOIDBondingCurve` and to `VOIDCoin`. Also consider `Ownable2Step` for the curve.

5. **Strengthen the post-conditions to verify the outcome, not just the outflow.** Have `migrate()` return the LP position identifier and the amounts actually deposited, and have `graduate()` assert that the position is owned by a pre-committed recipient recorded at construction. "The money left" is not the property you want to assert.

6. **Rehearse on a Base Mainnet fork before freezing anything** — this is already gate 5 in your `LAUNCH_GATES.md` and it is the right gate.

---

### H-01 — High — Forced ETH latches `graduationReady` early, closing the market and trapping every holder

**File:** `contracts/src/VOIDBondingCurve.sol` L58–60, L69, L133–138
**PoC:** `testH01_ForcedEthClosesCurveEarly`

`receive()` reverts, which is a good instinct, but it only guards ordinary value transfers:

```solidity
receive() external payable { revert DirectEthDisabled(); }
```

ETH can still be forced into any address by `selfdestruct`, by being named as a block's fee recipient, or by pre-funding the address before the contract is deployed. `_checkGraduation` reads `address(this).balance` — the raw balance, including forced ETH — and compares it against the threshold. Reserve accounting is done entirely by `address(this).balance` and `token.balanceOf(address(this))`, with no internal accounting of what was actually deposited through `buy()`.

**Attack:** with `virtualEthReserve = 1 ether` and `graduationThreshold = 10 ether`, one honest buyer has deposited 1 ETH. The attacker force-sends 9 ETH via `selfdestruct` and then buys for **1 wei**. `_checkGraduation` fires. The market is closed permanently.

```
receive() correctly reverts a 1 wei plain transfer  ✓
selfdestruct with 9 ETH succeeds                    ✓
1 wei buy latches graduationReady                   ✓
alice.sell(...) → CurveClosed()                     ✓
H-01 tokens still in curve at forced graduation: 449999999999999999959090909  (~450M VOID)
```

**Impact.** The attacker spends 9 ETH they do not recover, so this is griefing rather than profit-taking — but the cost is bounded by `graduationThreshold`, and you have not chosen that number yet. If you set a low threshold to make graduation reachable, you make this attack cheap. Consequences: every holder loses the ability to sell at a moment of the attacker's choosing; graduation occurs at a token/ETH ratio that reflects manipulation rather than demand, so the resulting pool is mispriced; ~450M VOID (half the launch allocation) goes into that pool on terms nobody agreed to; and combined with C-01, the trap is permanent if the adapter then fails.

A softer, likelier version of this needs no attacker at all: any genuine large buy that overshoots the threshold closes the market instantly for everyone behind it.

**Remediation.** Track deposits internally rather than reading raw balance:

```solidity
uint256 public ethReserve;   // only ever changed by buy(), sell(), graduate()

function buy(uint256 minimumTokensOut) external payable nonReentrant returns (uint256 tokensOut) {
    ...
    uint256 ethBefore = ethReserve;            // not address(this).balance - msg.value
    ...
    ethReserve = ethBefore + msg.value;
    ...
}
```

Do the same for the token side (`uint256 public tokenReserveInternal`), so donated VOID cannot skew pricing either. Then `_checkGraduation` compares `ethReserve` against the threshold, and forced ETH becomes inert dust rather than a control lever. Add a `sweepExcess()` that sends `address(this).balance - ethReserve` somewhere harmless.

Additionally, consider not latching the market shut at all — allow selling to continue right up until `graduate()` executes. There is no protocol reason a holder must be prevented from exiting during the window between "threshold reached" and "Safe executes," and that window is a multisig round trip, which can be hours or days.

---

### H-02 — High — Zero-fee, no-deadline curve makes sandwiching unconditionally profitable

**File:** `contracts/src/VOIDBondingCurve.sol` L85–117
**PoC:** `testH04_SandwichIsUnconditionallyProfitable`

The curve charges no fee in either direction. In a fee-bearing AMM, a sandwich must clear the round-trip fee before it profits, which sets a minimum victim size below which the attack is not worth running. Here that floor is zero: **any** buy of any size can be sandwiched profitably, limited only by the attacker's capital and gas.

```
H-04 victim expected tokens: 150,000,000 VOID      (quoteBuy before the front-run)
H-04 victim received tokens:  21,428,571 VOID      (86% worse)
H-04 attacker ETH profit:     0.900000000000000001 ETH   on a 1 ETH victim buy
```

The attacker captured 90% of the victim's deposit in value terms. That magnitude is a function of `virtualEthReserve` being small relative to trade size — a thin curve is a brutal one — which is precisely the parameter you have not frozen. But the *sign* of the attacker's profit is not parameter-dependent. It is always positive.

Three aggravating factors:

1. **`quoteBuy` / `quoteSell` are `view` functions over live balances.** The natural front-end pattern is quote-then-send, and the quote is stale the moment it is read.
2. **Neither `buy` nor `sell` accepts a deadline.** A transaction sitting in the queue can execute arbitrarily later, at an arbitrarily worse price. On Base this is currently constrained by the sequencer, but it is not eliminated, and it degrades if Base's ordering policy changes or when forced inclusion via L1 is used.
3. **Every test in the repository, and the pattern they model, passes `minimumTokensOut = 0`.** `testCurveHasNoAuctionDeadline`, `testBuyerEthTriggersSafeGatedGraduation`, and `testTradesCloseOnceGraduationIsReady` all do. The slippage guard exists and is well-implemented; nothing in the codebase demonstrates using it. Integrators copy tests.

**Remediation.**

- Charge a fee. Even 30–100 bps in each direction sets a real floor under sandwich profitability and accrues value to the protocol instead of to searchers. This also fixes L-02 for free, by giving rounding somewhere to be absorbed.
- Add a `deadline` parameter to `buy` and `sell` and revert past it.
- Fix the tests to use realistic non-zero `minimumTokensOut` / `minimumEthOut`, and document the quote-then-send pattern with an explicit slippage tolerance in `docs/`.
- Consider a per-transaction or per-block purchase cap during the early curve, when it is thinnest and manipulation is cheapest.
- Choose `virtualEthReserve` large enough that early trades do not move price catastrophically. This parameter is the difference between a survivable curve and the numbers above.

---

### H-03 — High — The treasury allocation can be sold back into the buyer-funded curve

**Files:** `contracts/src/VOIDLaunch.sol` L31; `contracts/src/VOIDBondingCurve.sol` L102–117
**PoC:** `testH03_TreasuryCanDrainBuyerEthThroughTheCurve`, `testI01_VestingHasNoCliffAndUnlocksFromDayOne`

Your brief states the invariant plainly: *"The creator deposits no real ETH liquidity. Buyers add all real ETH."* Both halves are true. What is not stated, and what the code permits, is that the creator can **withdraw** real ETH — by selling the treasury allocation into the curve that buyers funded.

`VOIDLaunch` creates the vesting wallet as:

```solidity
VestingWallet vesting = new VestingWallet(safe, uint64(block.timestamp), uint64(365 days));
```

OpenZeppelin's `VestingWallet` is **linear from `start`, with no cliff**. `start` is the deployment block. Tokens begin unlocking in the first second:

```
I-01 VOID released after 1 day: 273,972.6 VOID     // ~274k/day, every day, from day one
```

There is no restriction preventing those tokens from being sold into the curve. `sell()` checks only that the curve is open and has ETH.

```
Buyers deposit:                 9.000000 ETH
183 days elapse, treasury releases ~50.1M VOID
Treasury sells 50,136,986 VOID → 3.577712609970674487 ETH extracted
```

The treasury took 40% of the buyer-funded reserve in a single transaction, halfway through a schedule the market will read as a 12-month lock.

**On intent.** This may be deliberate. If so, it must be disclosed with total clarity, because "buyer-funded curve" and "12-month vesting" both read to a prospective holder as commitments that the creator's tokens cannot become the creator's ETH before graduation. If it is not deliberate, it is a serious hole in the economic model.

**Remediation.** Pick one and state it publicly:

- **Block treasury selling.** Add an ineligible-seller set (the vesting wallet and the Safe) checked in `sell()`, or require that treasury tokens can only be sold after graduation on the open venue.
- **Add a real cliff.** `new VestingWallet(safe, uint64(block.timestamp + CLIFF), uint64(365 days))`, with the cliff at or after expected graduation. This alone does not prevent selling, only delays it.
- **Disclose it exactly.** If the treasury may sell into the curve, say so in `docs/SECURITY.md` and in any public-facing material, in the same sentence as "buyer-funded."

Also relevant: `VestingWallet` in OZ 5.x is `Ownable` with the beneficiary as owner, so the Safe can transfer the vesting position to a third party, and can `renounceOwnership()` and brick the whole 100M allocation. See L-05.

---

## 5. Medium findings

---

### M-01 — Medium — Sell-side exit failure and a silent zero quote

**File:** `contracts/src/VOIDBondingCurve.sol` L75–83, L102–117
**PoC:** `testM01_LargeHolderCannotExitPosition`

The curve's virtual ETH reserve means the notional value of outstanding tokens always exceeds the real ETH held. `sell()` handles this by reverting rather than partially filling:

```solidity
ethOut = virtualEthReserve + ethBefore - ethAfterWithVirtual;
if (ethOut < 1 || ethOut > ethBefore) revert InsufficientCurveLiquidity();
```

A holder whose position is worth more than the curve's entire ETH balance cannot sell **any** of it in one call — the transaction reverts rather than filling what it can. In the PoC, Alice buys with 5 ETH, Bob buys with 1 ETH and exits first, and Alice can then no longer sell her full position at all. First-mover advantage on the way out is structural, and the design has a bank-run shape: the rational move on any bad news is to be first.

Worse, the read path fails silently:

```solidity
function quoteSell(uint256 tokensIn) public view returns (uint256 ethOut) {
    ...
    if (ethOut > ethBefore) return 0;     // silent zero, not a revert
}
```

A front end that computes `minimumEthOut` from `quoteSell` gets `0`, passes `0`, and has therefore disabled its own slippage protection at exactly the moment the curve is most stressed.

**Remediation.**
- Let `sell()` partially fill: cap `ethOut` at the available balance and compute the corresponding `tokensIn`, or expose `maxSellable()` so front ends can size the order.
- Make `quoteSell` revert with a named error, or return `(uint256 ethOut, bool ok)`, so a `0` cannot be mistaken for a valid quote.
- Document the exit dynamics for holders. The current `docs/` do not describe them.

---

### M-02 — Medium — `metadataURI` is never bound to the commitment

**File:** `contracts/src/VOIDCoin.sol` L109–123, L153–179
**PoC:** `testM02_SafeCanSubstituteAnyMetadataUri`

The commitment binds nine fields:

```solidity
keccak256(abi.encode(
    block.chainid, address(this), burnId, burner, burnAmount,
    proposedName, proposedSymbol, imageHash, salt
))
```

`metadataURI` is not among them. It arrives as a free parameter at approval time and is written straight to storage:

```solidity
function approveRename(..., string calldata metadataURI, bytes32 imageHash, bytes32 salt) external onlyOwner {
    ...
    if (bytes(metadataURI).length == 0 || bytes(metadataURI).length > 512) revert InvalidMetadataURI();
    bytes32 expected = proposalCommitment(burnId, slot.burner, slot.burnAmount, proposedName, proposedSymbol, imageHash, salt);
    if (expected != slot.commitment) revert CommitmentMismatch();
    ...
    _currentTokenURI = metadataURI;      // never checked against imageHash
}
```

There is no on-chain relationship between `imageHash` and `metadataURI`. Nothing verifies that the pinned content hashes to `imageHash`, that the URI is IPFS at all, or that it is immutable.

```
M-02 burner paid: 1,000,000 VOID  (and by the 10th rename, 10,000,000)
M-02 resulting URI: ipfs://completely-unrelated-content
```

I understand the design reason: the Safe pins a *cleaned* image, so the pinned artefact is not byte-identical to what the burner submitted and cannot be committed to in advance. That is a legitimate constraint. But the consequence is that a burner pays an escalating, permanent, non-refundable cost for an outcome the Safe can unilaterally alter, and the on-chain record cannot distinguish an honest cleaning from a substitution. `SECURITY.md` says commitments bind the "cleaned image hash," which reads as a stronger guarantee than the code provides.

**Remediation.** Options, roughly in order of strength:
1. Have the Safe compute the cleaned image's CID, publish it to the burner off-chain, and let the burner `replaceCommitment` to a commitment binding that exact CID. Then bind `metadataURI` into `proposalCommitment` and check it. Costs one extra round trip; closes the gap entirely.
2. Require `metadataURI` to be a CIDv1 whose multihash equals `imageHash`, verified on-chain by string parsing. More brittle, no round trip.
3. At minimum: emit `imageHash` and `metadataURI` together in `SkinChanged` (already done), and document precisely and prominently that the Safe controls the final URI and the burner is trusting it. Adjust `SECURITY.md`, which currently implies otherwise.

---

### M-03 — Medium — An unaccepted ownership transfer permanently disables renaming

**Files:** `contracts/src/VOIDLaunch.sol` L37; `contracts/src/VOIDCoin.sol` L75
**PoC:** `testM03_UnacceptedOwnershipPermanentlyDisablesRenaming`

`VOIDLaunch` initiates a two-step transfer in its constructor:

```solidity
coin.transferOwnership(safe);     // Ownable2Step: sets pendingOwner only
```

Until the Safe executes `acceptOwnership()`, the owner is `VOIDLaunch`. `VOIDLaunch` is a constructor-only contract: three immutable getters, no other functions, no fallback, no `receive`. It has no mechanism whatsoever to originate an external call.

```solidity
address(launch).call(abi.encodeWithSignature("setRenamePaused(bool)", false));  → false
address(launch).call(abi.encodeWithSignature("acceptOwnership()"));             → false
address(launch).call(hex"deadbeef");                                            → false
```

Meanwhile the constructor sets `renamePaused = true`. So in the window before acceptance — and permanently, if acceptance never happens because the Safe was misconfigured, the address was mistyped, the signers cannot reach threshold, or the deployment ran with a stale `SAFE_ADDRESS` — the token's owner is provably incapable of acting, renaming is stuck paused forever, and there is no recovery on a non-upgradeable contract.

`Deploy.s.sol` checks `safe.code.length > 0`, which catches a typo landing on an EOA but not a typo landing on a different contract, and not a Safe whose signer set cannot reach threshold.

**Remediation.**
- Make acceptance part of the deployment runbook with an explicit verification step: `token.owner() == safe` must be asserted before anything else proceeds. Your `LAUNCH_GATES.md` gate 4 says this; make it a hard, recorded check with the transaction hash.
- Consider having `VOIDLaunch` hold ownership deliberately with a `finalize()` function callable only by the pending owner, or add a time-boxed fallback owner, so a failed handoff is recoverable.
- Optionally, take the two-step handoff off the critical path entirely: deploy the token with the Safe as `initialOwner` directly, and have `VOIDLaunch` only move the allocation. `VOIDLaunch` never needs owner rights — it only needs to hold the tokens.

---

### M-04 — Medium — Griefing a queued Safe approval

**File:** `contracts/src/VOIDCoin.sol` L125–151, L153–179
**PoC:** `testM04_SupersedingBurnRevertsPendingSafeApproval`, `testM04_BurnerCanGriefTheSafeByReplacingTheCommitment`

`approveRename` requires an exact match on `burnId` and on the stored commitment. Two cheap actions invalidate a queued Safe transaction:

**Superseding burn.** A third party calls `burnForRename` at the next increment. `currentBurnId` advances, `_activeSlot` is overwritten, and the Safe's transaction reverts with `CommitmentMismatch`.

```
Alice burns 1,000,000 VOID and commits.
Safe queues approveRename(burnId = 1, ...).
Attacker burns 2,000,000 VOID before the Safe executes.
Safe executes → CommitmentMismatch()
Alice's 1,000,000 VOID is destroyed. She never got her rename. recordBurner is now the attacker.
```

This is documented behaviour ("a new successful burn supersedes the prior pending proposal without refunding"), and I am not calling the supersession rule a bug. What raises the severity is the **window**. A Safe transaction is not atomic with the burn — it requires signatures from a threshold of signers, and realistically that is hours to days. Any competing burner can wait until they see the Safe's transaction proposed and then supersede at the last moment. The attacker is not paying for a rename; they are paying to destroy someone else's, and they become the new record holder in the process.

**Free griefing by the burner.** `replaceCommitment` costs nothing and takes effect immediately. A burner who dislikes the moderation outcome can invalidate the Safe's transaction indefinitely — a permanent, zero-cost denial of the approval flow for that slot.

**Remediation.**
- Add a challenge delay: a new `burnForRename` sets a pending record that only becomes active after N blocks, so the Safe's queued transaction cannot be sniped at the last second.
- Add a commitment-freeze: once the Safe signals intent to approve (via an on-chain `lockSlot()` or by treating the slot as frozen after a delay), `replaceCommitment` reverts.
- Alternatively, have `approveRename` take the commitment hash and succeed on any slot whose commitment matches, rather than binding to the latest `burnId`.
- Document the supersession loss risk in the user interface — a burner about to spend millions of VOID should see, in plain language, that a later burner can void their proposal with no refund.

---

### M-05 — Medium — No slot expiry and no owner-side cancel

**File:** `contracts/src/VOIDCoin.sol` L16–22, L133, L138
**PoC:** `testM05_OwnerCannotClearAnUnapprovableSlot`

`RenameSlot.openedAt` is written on every burn and **never read anywhere in the contract**. There is no expiry. There is no owner function to clear a slot. `setRenamePaused(true)` stops new burns but leaves the existing slot in place.

A burner can therefore commit to something that can never be approved — the PoC uses a 16-character name, which `_validName` rejects for exceeding 15 — and the slot persists forever unless that burner voluntarily calls `replaceCommitment` or someone else pays the next increment to displace them.

```
approveRename(...) → InvalidName()
warp 3,650 days → activeSlot().burner is still alice
setRenamePaused(true) → activeSlot().burner is still alice
```

Aggravating case: if the burner is a smart contract that cannot call `replaceCommitment` — a vault, a timelock, a multisig that has lost its signers — the slot is stuck permanently and the only remedy is for a third party to burn the next increment.

**Remediation.**
- Add an expiry: `if (block.timestamp > slot.openedAt + SLOT_TTL)` allows anyone to clear the slot, which at least makes `openedAt` meaningful.
- Add `clearActiveSlot()` for the owner, emitting an event, for the unapprovable case. The burn stays destroyed either way — no refund semantics change — this only unblocks the mechanism.
- Consider validating the name and symbol **at burn time** rather than approval time. That is not possible with the current commit-reveal design, which is a genuine tension, but it means a user can irreversibly burn tokens for a proposal that was never valid.

---

## 6. Low and Informational findings

### L-01 — `VOIDLaunch` does not validate that `migrationTarget` has code

**PoC:** `testL01_LaunchAcceptsAnEoaMigrationTarget`

`Deploy.s.sol` L20 checks `migrationTarget.code.length > 0`, but `VOIDLaunch` L29 checks only `!= address(0)`. Anyone deploying `VOIDLaunch` directly — a different script, a fork test, a rehearsal, a future factory — can pass an EOA.

The failure mode is instructive. A high-level `try` call to a codeless address hits solc's `extcodesize` preamble, which reverts **before** the try body, so the `catch` never runs:

```
graduate() reverts with EMPTY revert data — not MigrationFailed()
10 ETH frozen forever
```

Only the `tokenReserve() != 0` post-condition prevents the ETH from being silently delivered to the EOA. Move the code check into the constructor, and be aware that `catch` does not cover the codeless-target case.

### L-02 — Rounding favours the trader on both sides

**PoC:** `testH02_RoundTripExtractsMoreEthThanDeposited`, `testFuzzH02_RoundTripAlwaysReturnsAtLeastTheDeposit`, `testH02_RepeatedRoundTripsCompoundTheLeak`, `testInvariant_CurveEthNeverExceedsNetDeposits`

Both sides floor the divisor-side quantity, so both round in the user's favour:

```solidity
uint256 tokensAfter = invariant / (virtualEthReserve + ethBefore + msg.value);   // floor → tokensOut rounds UP
uint256 ethAfterWithVirtual = invariant / (tokensBefore + tokensIn);             // floor → ethOut rounds UP
```

An atomic buy-then-sell round trip therefore returns **more** ETH than it deposited, always:

```
H-02 deposited: 1000000000000000000 wei
H-02 returned:  1000000000000000001 wei
H-02 curve ETH lost: 1 wei per round trip; 200 wei over 200 round trips
```

The fuzz test confirms `ethOut ≥ ethIn` holds across the input space. Economically this is negligible — 1 wei against Base gas costs is not an attack — but it means the invariant *"the curve's ETH balance is at least the sum of net deposits"* is **false**, which matters for two reasons: the shortfall is paid out of other buyers' ETH, and there is no fee to absorb it. Fix by ceiling the divisor-side quantity in both directions (`Math.ceilDiv`) so rounding favours the pool, and add the invariant test (see I-04). Introducing a fee (H-02) makes this moot.

### L-03 — `evm_version` is not pinned

`contracts/foundry.toml` pins `solc_version = "0.8.30"`, `optimizer = true`, `optimizer_runs = 200` — but not `evm_version`. The resolved value comes from the Foundry default, which on the version I used is `prague`:

```
$ forge config --root contracts
evm_version = "prague"      # from the toolchain default, not from foundry.toml
```

Different Foundry versions default differently. Two people building the same commit with different Foundry versions get different bytecode, which breaks the reproducibility guarantee your deliverables list asks for, and could target an EVM version Base does not support. Add `evm_version = "cancun"` (or whichever Base fork level you have verified) to `foundry.toml` explicitly, and pin the Foundry version in CI. Also note `bytecode_hash = "ipfs"` and `cbor_metadata = true` embed a metadata hash sensitive to compilation paths — set `bytecode_hash = "none"` if you want byte-identical rebuilds.

### L-04 — The rename mechanism self-terminates after 44 renames

**PoC:** `testL02_RenameMechanismSelfTerminates`

`nextBurnRequirement()` is `recordBurn + 1,000,000e18`, monotonically increasing and never reset. Cumulative burn after *n* renames is `n(n+1)/2` million VOID:

```
L-02 max lifetime renames before supply exhaustion: 44
L-02 cumulative burn at that point: 990,000,000 VOID  (99% of original supply)
```

Well before that, the requirement exceeds the free float and the mechanism becomes practically dead. This is arguably by design — the escalation is the point — but it is not documented anywhere, and "escalating: 1M, 2M, 3M, onward" reads as unbounded. Document the ~44-rename ceiling and the supply-exhaustion dynamic.

### L-05 — The `VestingWallet` is renounceable and transferable

**PoC:** `testI01_VestingHasNoCliffAndUnlocksFromDayOne`

OZ 5.x `VestingWallet` is `Ownable`, with the beneficiary as owner. The Safe can therefore `renounceOwnership()`, permanently bricking 100,000,000 VOID (10% of supply, unrecoverable), or transfer the vesting position to any third party without the schedule changing. Neither is described in your documents. If the treasury allocation is meant to be non-transferable, wrap it.

### L-06 — No deadline parameter on `buy` / `sell`

Covered under H-02. Both functions can execute arbitrarily long after signing, at an arbitrarily different price. Add `uint256 deadline` and revert past it.

### L-07 — `quoteSell` returns `0` instead of reverting

Covered under M-01. A silent `0` is indistinguishable from a legitimate quote of zero and disables downstream slippage protection.

---

### Informational

**I-01 — Unreachable check.** `VOIDCoin.sol` L164:
```solidity
if (slot.burner != recordBurner || slot.burnAmount != recordBurn) revert CommitmentMismatch();
```
`_activeSlot`, `recordBurner`, and `recordBurn` are only ever written together in `burnForRename`; `replaceCommitment` touches only `commitment`; `delete` is caught by the earlier `NoActiveSlot` check. This condition can never be true. Harmless, but it is defensive code that reads as if it protects something and does not — either remove it or add a comment explaining the invariant it documents.

**I-02 — `openedAt` is dead state.** Written on every burn, never read. Costs a storage slot write. See M-05 — either use it for expiry or remove it.

**I-03 — `try/catch` in `graduate()` discards diagnostics.** Every failure mode collapses to `MigrationFailed()`, with no revert reason bubbled and no event. Debugging a failed graduation on Mainnet with all funds locked is exactly when you will want that data. Bubble the reason, or at minimum emit an event with the raw return data before reverting. Also note the 63/64 gas rule: a target that consumes nearly all forwarded gas can leave insufficient gas for the catch path.

**I-04 — `VOIDBondingCurve` has no fuzz or invariant coverage.** This is the most consequential gap in the test suite. Both invariant tests target `VOIDCoin` metadata and are driven by a handler with two functions that are supposed to fail — zero of 128,000 calls reverted, meaning the handler never exercised a meaningful state transition. The contract holding all the money has five happy-path unit tests. At minimum, add invariants for:
- `address(this).balance >= sum of net ETH deposits` (currently **false** — L-02)
- `ethOut ≤ ethIn` for any atomic buy→sell round trip (currently **false** — L-02)
- `tokenReserve() + sum(tokens held by buyers) == LAUNCH_ALLOCATION` across arbitrary trade sequences
- `graduationReady` is only ever set by ETH arriving through `buy()` (currently **false** — H-01)
- No sequence of trades leaves the curve unable to honour the smallest possible sell
- `graduated == true` implies `balance == 0 && tokenReserve() == 0`

Add a proper handler-based invariant suite with a bounded actor set, random buy and sell amounts, and forced-ETH actions. The four failing invariants above are exactly the findings in this report, which is the point: they would have been caught in-house.

**I-05 — Static analysis should not be a launch gate.** `LAUNCH_GATES.md` gate 1 lists "zero Slither findings" as a gate. Slither returns zero here and the protocol has a Critical issue. Keep running it — regressions matter — but do not let a green result carry weight in the go/no-go decision.

**I-06 — Metadata caching after rename.** Already correctly flagged in `SECURITY.md`. Worth restating: wallets, explorers, aggregators, and AMM front ends cache ERC-20 `name()` and `symbol()` aggressively and inconsistently. A renamed token will present differently across venues for an unpredictable period. This is a user-safety and impersonation surface — a token that renames itself to match a well-known asset on some surfaces but not others is a phishing primitive. `_validName` allows any ASCII alphanumeric string of ≤15 characters, so the moderation policy is the only thing preventing a rename to a lookalike of a major token.

**I-07 — `recordBurn` and `recordBurner` persist after approval.** `approveRename` deletes `_activeSlot` but leaves `recordBurn` and `recordBurner`. This is correct for the escalation ratchet, and the code is right, but it means `recordBurner` reports the last *successful record holder* even after their proposal was applied and the slot is empty. Worth a natspec comment so integrators do not read it as "there is an active proposal by this address."

---

## 7. Answers to your specific adversarial review requests

| # | Your request | Result |
|---|---|---|
| 1 | Access control, Safe handoff, unauthorized metadata/graduation paths | No unauthorized path found. `onlyOwner` gating is correct on `approveRename`, `setRenamePaused`, `graduate`. **But:** M-03 (handoff can strand the token), C-01 failure mode 2 (`renounceOwnership` is live on the curve), M-02 (the Safe's metadata power exceeds what the commitment binds). |
| 2 | Supply accounting, burns, escalation, stale transactions, replay/collision | **Clean.** `abi.encode` (not `encodePacked`) prevents collision; `block.chainid` and `address(this)` prevent cross-chain and cross-contract replay; the stale-amount check reverts before any burn; escalation is exact and not caller-selectable. This part of the codebase is well built. Minor: L-04 (self-termination), I-01, I-07. |
| 3 | Buy/sell mathematics, rounding, overflow, reserves, insolvency, manipulation, sandwiching | **Multiple issues.** H-02 (sandwiching is unconditionally profitable at zero fee), H-01 (reserve accounting uses raw balance and is manipulable), M-01 (exit failure and silent zero quote), L-02 (rounding favours the trader in both directions). No overflow: max invariant ≈ 9e47 against a 1.15e77 ceiling, comfortably safe. |
| 4 | Reentrancy, malicious receivers/sellers, failed ETH delivery, arbitrary calls, approvals, return handling | **Clean.** `nonReentrant` on all three state-changing functions and they share a guard; correct CEI ordering (`graduated = true` before the external call); `SafeERC20` throughout; `Address.sendValue` bubbles failures; the token has no hooks so `safeTransfer` cannot reenter; `forceApprove` is used correctly. No finding. |
| 5 | Graduation transitions, rollback, stranded funds, DoS, malicious target | **C-01, the report's headline.** Rollback works in the narrow sense (a reverting `migrate` reverts the whole transaction) but that is the problem: it leaves the market permanently closed with no other exit. Malicious targets pass every post-condition. Also L-01. |
| 6 | Front-running, griefing, supersession, moderation delay, unapprovable commitments | **M-04** (superseding burn and free `replaceCommitment` both invalidate the Safe's queued transaction; multisig latency widens the window), **M-05** (unapprovable commitments persist with no owner-side clear), **H-01** (forced-ETH griefing). |
| 7 | Constructor/deployment misconfiguration, invalid Safe or target, acceptance failure, deployer privilege | **M-03** (acceptance failure is unrecoverable), **L-01** (`VOIDLaunch` accepts an EOA target where the script does not). Positive: the deployer genuinely retains no authority once acceptance completes — `VOIDLaunch` has no owner-call forwarding surface, which I verified directly. `LaunchAllocationNotConsumed` correctly asserts the allocation is fully moved. |
| 8 | Vesting start, beneficiary, allocation, circulating-supply interaction | **H-03.** Allocation amounts are exactly correct (900M / 100M, verified). Start time and beneficiary are correct. The issues are semantic: no cliff (≈274k VOID/day liquid from day one), treasury tokens are sellable into the buyer-funded curve, and the wallet is renounceable and transferable (L-05). |
| 9 | Base-specific assumptions and post-graduation venue compatibility | **Not assessable at this commit.** The venue is unchosen and the adapter unwritten. Base-relevant observations: L-03 (`evm_version` unpinned), H-02's severity is currently damped by Base's single sequencer but not eliminated, and forced-ETH (H-01) works identically on any OP Stack chain. |
| 10 | Missing tests, invariants, properties that should block Mainnet | **I-04.** The curve has zero fuzz and zero invariant coverage. Six specific properties are listed in I-04; four of them currently fail. |

---

## 8. Reproducing this review

```bash
git clone https://github.com/rockomatthews/voidcoin.git
cd voidcoin
git checkout 18e79a24576fe2a028bf17706342989e96fec0d8
npm ci

# Baseline, as claimed in the brief — reproduced exactly:
forge test --root contracts
#   → 17 passed, 0 failed
VOIDCOIN_SOLC_BIN=$(which solc) npm run contracts:security
#   → 22 contracts, 101 detectors, 0 results

# Then add the delivered PoC file and re-run:
cp AuditPoC.t.sol contracts/test/
forge test --root contracts -vv
#   → 36 passed, 0 failed  (17 existing + 19 proofs of concept)
```

**Toolchain used:** Foundry `forge 1.5.1-stable`, solc `0.8.30+commit.73712a01`, Slither `0.11.6`, OpenZeppelin Contracts `5.6.1`, optimizer on at 200 runs, `evm_version` resolved to `prague`.

Every PoC is written to **pass**, asserting the presence of the issue. Where the correct assertion for sound behaviour is the inverse (`testFuzzH02_RoundTripAlwaysReturnsAtLeastTheDeposit`, `testInvariant_CurveEthNeverExceedsNetDeposits`), the comment in the test says so explicitly. After you fix the underlying issues, those tests should be inverted and kept as regression tests.

---

## 9. Commercial guidance (informational, not a bid)

You asked for a quote, a timeline, and a separate phase-two quote. I cannot provide any of these as an offer — see Section 0. What follows is market context to help you budget and to help you evaluate the bids you do receive.

**Typical phase-one pricing** for a scope of this size — roughly 400 lines of in-scope Solidity across three contracts, plus a script, with novel economic mechanics — from a reputable firm in 2026 runs approximately **$15,000–$45,000**, over **1–3 weeks** of calendar time. The wide range reflects real differences: the top tier prices on scarcity and their sign-off carries weight with listing venues and partners; mid-tier firms do comparable technical work for a third of the price with less brand value. Line-count is a poor predictor here — the bonding curve's economics will consume more reviewer hours than its 139 lines suggest.

**Phase two — the delta review** after the adapter, Safe, parameters, and calldata are frozen — is usually **30–50% of phase one**, over **3–7 days**. In your case I would expect it at the upper end or beyond, because the migration adapter is not a delta at all. It is new code integrating with an external AMM, and AMM integration bugs (tick alignment, initialisation price, slippage on the initial mint, LP position custody) are a well-populated category of expensive failures. Budget for it as a small standalone audit rather than a re-check.

**Three things that will lower your bill.** First, fix C-01 before you get quotes — a firm that finds a Critical has to write it up, re-review your fix, and re-test, and that is billable. Second, close the I-04 coverage gap; suites with real invariants signal a codebase that will not surprise the reviewer. Third, freeze your parameters *before* the engagement rather than during it, since a parameter change mid-review invalidates the economic analysis.

**What to ask any firm you approach.** Whether the same reviewers do the fix re-test. Whether the adapter review is in scope or a change order. Whether they will run their own invariant/fuzz campaign or only read code. And — given C-01 — whether they will review the *graduation design*, not just its implementation, because a firm that only checks the code as written will confirm `graduate()` does exactly what it says and miss the point entirely.

---

## 10. Conclusion and recommended gates

**Do not deploy to Base Mainnet at this revision.**

Your own position is right, and I want to be precise about where I diverge from it. You wrote that the protocol is not cleared for Mainnet until the migration adapter, Safe, parameters, and calldata are frozen and receive phase-two review. That is necessary and it is not sufficient. **C-01 is not a parameter problem.** Freezing a correct adapter address reduces the probability that the adapter is broken or malicious; it does nothing about the fact that the curve has no answer if it turns out to be either. A protocol whose users' entire capital depends on one transaction to one immutable address, with sells already disabled and no timeout, is fragile independent of how carefully you choose that address.

### Before any Mainnet deployment

1. **Fix C-01 structurally.** Abort path, timelocked emergency exit, disabled renunciation, and outcome-verifying post-conditions. This is a design change and should be treated as one.
2. **Fix H-01** by tracking reserves internally instead of reading raw balances.
3. **Decide and disclose H-03.** Either block treasury selling into the curve, or state clearly that it is permitted. Do not leave it implicit.
4. **Address H-02** with a fee and a deadline parameter, and fix the tests that model zero slippage tolerance.
5. **Resolve the Mediums**, particularly M-03 (handoff verification is a runbook change, cheap) and M-02 (a documentation fix is acceptable if the round-trip commitment is too costly).
6. **Build the curve invariant suite** in I-04. Four of those six properties currently fail; they are your regression tests for this report.
7. **Then** commission a paid audit from a firm that will sign its name to the result.
8. **Then** phase two on the frozen adapter, Safe, parameters, and calldata — treating the adapter as new code, not as a delta.
9. **Fork-rehearse the whole sequence** on Base Mainnet fork, including a deliberately failing `migrate()`, to confirm your abort path works before real money is involved.

### What is genuinely good here

It is worth saying plainly, because it is unusual: the token contract is well built. The commit-reveal scheme is correctly domain-separated with chain ID and contract address, uses `abi.encode` rather than `encodePacked` so field-boundary collisions are impossible, checks the expected burn amount before burning anything so stale transactions cost nothing, and makes the escalation exact and non-selectable. Reentrancy protection is thorough and correctly ordered. `SafeERC20` is used consistently. The deployer really does end up with no authority. The supply is genuinely fixed with no mint, tax, blacklist, seizure, or transfer pause. The documentation in `docs/` is unusually honest — `SECURITY.md` names the migration adapter as a risk before any auditor did.

The problems are concentrated in one contract and one design decision. That is a much better place to be than the alternative, and it is fixable.

---

*Prepared by Claude (Anthropic). This document is a technical review, not a professional audit opinion. No warranty, liability, or certification attaches to it. It does not constitute financial, investment, or legal advice. Security review reduces risk; it does not eliminate it, and no review can prove the absence of vulnerabilities.*


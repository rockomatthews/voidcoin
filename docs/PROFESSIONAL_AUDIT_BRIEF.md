# VOIDCOIN professional security review brief

## Repository and frozen revision

- Repository: `https://github.com/rockomatthews/voidcoin`
- Review commit: `18e79a24576fe2a028bf17706342989e96fec0d8`
- Intended chain: Base Mainnet, chain ID `8453`
- Deployment status: not deployed
- Solidity: exact `0.8.30`
- Optimizer: enabled, 200 runs
- OpenZeppelin Contracts: resolved version `5.6.1` in `package-lock.json`

Please review only the frozen commit above. Any later change requires a documented delta review before deployment.

## Primary contract scope

- `contracts/src/VOIDCoin.sol`
- `contracts/src/VOIDBondingCurve.sol`
- `contracts/src/VOIDLaunch.sol`
- `contracts/script/Deploy.s.sol`
- `contracts/test/VOIDCoin.t.sol`
- `contracts/test/VOIDLaunch.t.sol`
- `contracts/foundry.toml`

The Next.js moderation application is not part of the core Solidity audit unless separately quoted. We would welcome an optional integration review of commitment construction, transaction calldata, receipt validation, Safe approval preparation, and event indexing under `src/app/api` and `src/lib`.

## Intended behavior and invariants

### Token and identity control

- Non-upgradeable ERC-20 with an original supply of exactly `1,000,000,000e18`.
- No minting after construction, transfer tax, blacklist, seizure, or transfer pause.
- Genesis allocation: `900,000,000e18` to the buyer-funded curve and `100,000,000e18` to a 12-month `VestingWallet` benefiting the production Safe.
- The first rename challenge burns exactly `1,000,000e18`; subsequent challenges burn exactly `2,000,000e18`, `3,000,000e18`, and onward.
- Callers cannot choose a cheaper or larger amount. A stale expected amount must revert before any burn.
- A new successful burn supersedes the prior pending proposal without refunding any previous burn.
- Only the current record holder may replace the active commitment without another burn.
- Commitments bind chain ID, token address, burn ID, burner, exact burn amount, proposed name, proposed symbol, cleaned image hash, and salt.
- Only the owner Safe may apply a commitment-matching identity. Ownership uses `Ownable2Step`.
- The Safe may pause new rename burns but cannot pause token transfers.

### Buyer-funded curve and graduation

- The creator deposits no real ETH liquidity.
- Buyers add all real ETH through an indefinite constant-product bonding curve with a virtual ETH reserve.
- Holders may sell back into the curve while it remains open and real ETH liquidity is available.
- Trading closes when real ETH reaches the configured graduation threshold.
- Only the Safe may call graduation.
- Graduation must atomically move all remaining curve tokens and real ETH through a separately reviewed migration target, or revert without losing funds.

### Launch and authority

- Deployment atomically creates the vesting wallet, token, and curve.
- The launch factory temporarily owns the token only to initiate two-step transfer to the Safe.
- The curve is owned by the Safe from construction.
- Renaming starts paused.
- The deployer must retain no protocol authority after the Safe accepts token ownership.

## Areas where we specifically request adversarial review

1. Access control, Safe handoff, and any path to unauthorized metadata changes or graduation.
2. Supply accounting, permanent burns, escalating-burn enforcement, stale transaction behavior, and commitment replay/collision risks.
3. Buy/sell mathematics, rounding, overflow, reserve accounting, insolvency, price manipulation, sandwiching, and economically exploitable edge cases.
4. Reentrancy, malicious ERC-20 receiver/seller contracts, failed ETH delivery, arbitrary calls, approvals, and token-transfer return handling.
5. Graduation state transitions, failed migration rollback, stranded ETH/tokens, denial of service, and malicious migration-target behavior.
6. Front-running, griefing, record-holder supersession, moderation delays, and ways a user could burn tokens but create an unapprovable commitment.
7. Constructor/deployment misconfiguration, invalid Safe or migration target, ownership acceptance failure, and deployer privilege retention.
8. Vesting start time, beneficiary, allocation correctness, and interactions between vesting and circulating-supply claims.
9. Base-specific assumptions and compatibility with the selected post-graduation Base liquidity venue.
10. Missing tests, invariants, or properties that should block Mainnet deployment.

## Known unfinished Mainnet inputs

These are intentionally not frozen and therefore cannot receive final audit sign-off yet:

- Production Safe address and threshold.
- Migration-target implementation/address for the final Base liquidity venue.
- Virtual ETH reserve.
- Graduation threshold.
- Pool fee, price range, LP/position recipient, and lock/custody arrangement.
- Permanent genesis IPFS metadata URI.

Please quote the current review as phase one and identify the cost and turnaround for a required phase-two delta review after the migration adapter, parameters, Safe, and deployment calldata are frozen. No Mainnet deployment will occur before that delta review.

## Reproduction commands

```bash
git clone https://github.com/rockomatthews/voidcoin.git
cd voidcoin
git checkout 18e79a24576fe2a028bf17706342989e96fec0d8
npm ci
forge fmt --check --root contracts
forge test --root contracts
npm run contracts:security
```

The canonical security command requires Slither `0.11.6` or newer and the exact Solidity `0.8.30` compiler. It compiles the complete `VOIDLaunch` dependency graph directly with `solc`, bypassing the unresolved-reference problem in the current Foundry build-info ingestion path.

Current baseline at the frozen revision:

- 17 Foundry tests passed, including fuzz and invariant suites.
- Each invariant ran 128,000 calls.
- Slither analyzed 22 contracts with 101 non-timestamp detectors and reported zero findings and no parser errors.
- GitHub Actions application and contract jobs passed.
- Production npm dependency audit reported zero known vulnerabilities.

These automated results are supporting evidence only, not a substitute for independent review.

## Requested deliverables

- A written report with Critical, High, Medium, Low, and Informational severity ratings.
- Concrete exploit scenarios or proofs of concept for every actionable issue.
- Remediation guidance tied to exact files and lines.
- Review of our fixes and a final retest statement.
- A list of accepted risks and unresolved assumptions.
- Confirmation of the final reviewed commit, compiler settings, dependency versions, and bytecode/build reproducibility.
- A clear statement of what remains outside the review, especially the unfinished migration target and economic parameters.

Please do not request private keys or seed phrases. Deployment credentials will never be shared with an auditor.

# VOIDCOIN V2 independent delta review

## Verdict requested

Confirm whether the frozen V2 commit is suitable for Base Mainnet deployment. Report Critical, High, Medium, Low, and Informational findings with reproducible proof-of-concept tests. Mainnet is blocked on every unresolved Critical or High.

## New production scope

- `contracts/src/VOIDCoinV2.sol`
- `contracts/src/VOIDV2Launch.sol`
- `contracts/src/VOIDV2BuyRouter.sol`
- `contracts/script/DeployV2.s.sol`
- `contracts/test/VOIDCoinV2.t.sol`
- `contracts/test/VOIDV2Launch.t.sol`
- `contracts/test/VOIDV2BuyRouter.t.sol`
- `contracts/test/VOIDV2Launch.fork.t.sol`

Inherited scope that V2 directly uses:

- `contracts/src/VOIDCoin.sol`
- `contracts/src/VOIDPositionLocker.sol`
- OpenZeppelin `VestingWallet`, ERC-20, ownership, safe-transfer, and reentrancy dependencies pinned by the lockfiles.

V1 bonding curve, migration, graduation executor, and V1 deployment script are not used by the V2 launch.

## Frozen economics

- Original supply: 1,000,000,000 VOID.
- LP allocation: 980,000,000 VOID less atomically burned position-manager rounding dust.
- Creator allocation: 20,000,000 VOID, linear vesting for 365 days from deployment.
- First takeover: 1,000,000 VOID.
- Next takeover: maximum of prior record +250,000 VOID and prior record +10%, rounded up.
- Strategic overburn cap: 2,000,000 VOID above the live floor.
- VOID/USDC pool fee: 1%.
- WETH/USDC routing fee: 0.05%.
- Opening spot target: approximately $0.000001 per VOID.
- LP lock: 365 days.

## Required confirmations

1. Both token-address orderings create the intended token-only position and the first USDC-for-VOID swap moves price upward in dollar terms.
2. The opening integral cost of approximately 1,000,000 VOID is approximately $1, including the 1% pool fee and tick rounding.
3. A predicted/preinitialized hostile pool can only revert deployment, cannot redirect assets, and a fresh deployment salt plus private broadcast is a sufficient operational recovery.
4. The constructor never consumes USDC, never leaves VOID in the launch contract, and cannot mint the LP NFT anywhere except the immutable locker.
5. Position-manager rounding dust is bounded, atomically burned, and cannot touch the 2% vesting allocation.
6. The deployed Safe owns token metadata authority from construction; the deployer owns no protocol authority.
7. The fixed and 10% takeover rules use the larger result at every boundary, round upward, and preserve the 2,000,000-token strategic cap.
8. `buyWithETH` spends all input or reverts, honors minimum output, cannot retain or sweep assets, and is safe under callback/reentrancy attempts.
9. The fixed WETH 0.05% → USDC → VOID 1% path matches live Base deployments and remains functional on a Base Mainnet fork.
10. A buyer can sell through normal Uniswap routing after buys have placed USDC in the pool.
11. The position can be released only after 365 days and only to the immutable Safe beneficiary; confirm the Safe can receive the NFT.
12. Dynamic `name()`, `symbol()`, and `tokenURI()` still change together only after a valid record burn, commitment, and Safe approval.
13. Contract bytecode and initcode fit Base limits, source verifies with Solidity 0.8.30, and the deployment script uses only official Base addresses.

## Reproduction

```bash
cd /Users/rob/Desktop/voidcoin/contracts
forge fmt --check
forge test --match-path 'test/VOID*V2*.t.sol' -vvv
set -a
source ../.env.local
set +a
forge test --match-path 'test/VOIDV2Launch.fork.t.sol' -vvvv
```

The fork test must run, not skip. Record the Base block number and RPC provider. Add adversarial tests rather than relying on the included happy-path mocks.

## Builder evidence before independent review

- QuickNode Base Mainnet fork block: `50113189`.
- An exact `1.000000 USDC` genesis swap through official Base `SwapRouter02` returned
  `1,000,334.084833147896168246 VOID`, enough for the initial `1,000,000 VOID` takeover.
- The same fork suite completed a real ETH → WETH → USDC → VOID purchase and a VOID → USDC sale.
- Unit deployment tests exercise both token-address orderings and their symmetric starting prices and ranges.
- These are builder results, not substitutes for the requested independent review.

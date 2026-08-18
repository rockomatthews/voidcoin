# VOIDCOIN V2 launch gates

No later gate approves an earlier gate. V1 deployment authority and V2 deployment authority are separate.

## 1. Local verification

- `forge fmt --check`, all Foundry tests, application tests, lint, and production build pass.
- V2 unit tests prove the fixed-plus-percentage takeover boundary and strategic overburn cap.
- V2 launch tests prove token-only liquidity, zero USDC use, 98/2 allocation, dust burning, hostile-price rejection, and immutable LP custody.
- V2 buy-router tests prove arbitrary positive inputs, slippage rollback, exact routing, and zero retained assets.
- Slither scans `VOIDCoinV2`, `VOIDV2Launch`, `VOIDV2BuyRouter`, and inherited production dependencies with Solidity 0.8.30.

## 2. Base Mainnet fork

- Run `VOIDV2Launch.fork.t.sol` with the configured private QuickNode RPC and confirm it does not skip.
- Prove the pool is created through the official Base Uniswap v3 position manager.
- Prove the LP NFT is minted directly to the 365-day locker.
- Execute a real ETH → WETH → USDC → VOID purchase through official `SwapRouter02`.
- Execute an exact 1 USDC genesis purchase and prove it acquires at least the initial 1,000,000 VOID takeover.
- Confirm price moves upward in dollar terms for both possible token-address orderings.
- Add and pass a normal Uniswap sell test after the first buy.
- Record the exact fork block used for release evidence.

## 3. Independent V2 delta review

- Freeze a commit and send `V2_AUDIT_HANDOFF.md` plus the complete scoped source and tests.
- Resolve every Critical and High finding and retest the exact remediation commit.
- Record accepted Medium and Low findings.
- Freeze bytecode, compiler, optimizer, dependencies, Base addresses, deployment salt strategy, and deployment calldata.

## 4. Production inputs and dry run

- Explicitly approve the production Safe and confirm its threshold.
- Confirm the Safe can receive the LP NFT when the locker releases it after 365 days.
- Explicitly approve the 2% creator allocation and vesting start at V2 deployment.
- Verify the permanent genesis metadata URI contains the V2 token contract address, `https://voidcoin.fun`, description, and social links.
- Generate a fresh random `V2_DEPLOYMENT_SALT`; never commit it.
- Predict the CREATE2 launch address and derived token/pool addresses.
- Confirm the intended VOID/USDC 1% pool is uninitialized immediately before broadcast.
- Rehearse the exact script against a fresh Base fork.

## 5. Mainnet broadcast

- Obtain explicit user authorization for the V2 Mainnet broadcast after the audit and dry-run evidence are complete.
- Use a private transaction path to reduce predictable-pool preinitialization griefing.
- Deploy and verify `VOIDV2Launch`, `VOIDCoinV2`, `VOIDV2BuyRouter`, the locker, and the vesting wallet.
- Confirm the Safe owns token authority and the deployer owns none.
- Confirm the pool starts at the intended tick, holds the LP allocation, and the LP NFT is registered in the locker.
- Confirm `renamePaused()` remains true.

## 6. Application activation

- Set `NEXT_PUBLIC_VOIDCOIN_V2_ADDRESS`, `NEXT_PUBLIC_VOID_V2_BUY_ROUTER_ADDRESS`, and the V2 deployment block in Vercel Preview.
- Verify live quotes and purchases on desktop and mobile with 1% output protection.
- Verify the connected wallet immediately reads the V2 token balance.
- Verify the name, ticker, image, header, hero, title, and archive all follow the V2 token state.
- Promote the tested preview to production only after the contract and site addresses match.

## 7. Discovery and first trade

- Execute one explicitly approved small production purchase so the pool has a swap history.
- Verify the exact Base App coin URL, Uniswap token URL, BaseScan token page, and DexScreener pair.
- Submit the verified website, logo, description, and social fields to BaseScan and other indexers.
- Keep the metadata-caching warning visible: third-party wallets and indexes may lag an onchain rename.
- Have the Safe unpause renaming only after moderation and notifications are live.

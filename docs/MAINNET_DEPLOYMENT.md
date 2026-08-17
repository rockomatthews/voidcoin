# Base Mainnet deployment runbook

VOIDCOIN supports Base Mainnet only. The application hard-codes chain ID `8453`; it ignores stale test-chain environment variables.

## Required decisions and deployed dependencies

Do not broadcast until all values are final and independently reviewed:

- `SAFE_ADDRESS` — deployed production Safe that will moderate metadata and own the curve. Its fallback handler must accept ERC-721 safe transfers.
- `INITIAL_TOKEN_URI` — permanent IPFS JSON for the supplied VOID logo and genesis identity.
- `BASE_MAINNET_RPC_URL` — production Base RPC.
- `BASESCAN_API_KEY` — source-verification credential.
- A funded deployment signer selected through Foundry's encrypted keystore (`--account`) or hardware-wallet (`--ledger` / `--trezor`) flow. Never place a raw private key in Vercel or repository environment files.

The deployment script is Base Mainnet-only. It hardcodes the owner-approved 100 ETH virtual reserve, 1 ETH maximum purchase, ratio-matched 0.1% pool seed, 25 ETH buyer-funded graduation threshold, and price-continuity burn of excess unsold inventory; pins the official Uniswap v3 NonfungiblePositionManager at `0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1` and SwapRouter02 at `0x2626664c2603336E57B271c5C0b26F421741e481`; deploys the migration adapter, atomic graduation executor, and immutable 12-month position locker; refuses an EOA or non-ERC721-receiving Safe; and refuses empty genesis metadata.

## Rehearse without broadcasting

Run the full script against a local Base Mainnet fork first:

```bash
anvil --fork-url "$BASE_MAINNET_RPC_URL"
forge script contracts/script/Deploy.s.sol:DeployVOIDCoin \
  --root contracts \
  --rpc-url http://127.0.0.1:8545 \
  --sender "$DEPLOYER_ADDRESS" \
  -vvvv
```

Verify the predicted addresses, 980M/20M allocation, direct Safe ownership, 1% buy/sell fee, 100 ETH virtual reserve, 1 ETH purchase cap, 25 ETH buyer-funded threshold, ratio-matched capped pool seed, exact excess-inventory burn formula, graduation-gated treasury vesting, migration adapter, atomic executor, 12-month LP locker, Safe ERC-721 reception, and paused rename state.

## Broadcast and verify

This is an explicit Mainnet spending gate:

```bash
forge script contracts/script/Deploy.s.sol:DeployVOIDCoin \
  --root contracts \
  --rpc-url base_mainnet \
  --account voidcoin-deployer \
  --broadcast \
  --verify \
  -vvvv
```

Import the deployment wallet into Foundry's encrypted keystore interactively with `cast wallet import voidcoin-deployer --interactive`, or replace `--account voidcoin-deployer` with a supported hardware-wallet flag. The deployment wallet is only a gas payer; the deployed production Safe owns the protocol contracts directly.

After broadcast:

1. Record the launch, token, curve, vesting, migration-adapter, graduation-executor, and position-locker addresses.
2. Confirm the Safe already owns both token and curve and the deployer has no protocol authority.
3. Confirm the 20M creator allocation cannot release before successful graduation and the LP NFT cannot release for 365 days after graduation.
   Record the Safe fallback-handler address and prohibit changing it during the lock unless the replacement is independently proven to return `IERC721Receiver.onERC721Received.selector` through the Safe.
4. Set Vercel `NEXT_PUBLIC_VOIDCOIN_ADDRESS` and `NEXT_PUBLIC_VOIDCOIN_DEPLOYMENT_BLOCK`.
5. Configure the production RPC, database, private Blob store, Pinata, Resend, Alchemy webhook, admin email, WalletConnect ID, and secrets.
6. Keep renaming paused until moderation, event indexing, email, and Safe calldata are verified against the live address.
7. Add a separate external Base trading link only after liquidity is live and independently verified.

## Graduation operation

1. The Safe verifies the active migration target and calls `seedMigrationPool()`.
2. Simulate `VOIDGraduationExecutor.execute(maximumTokenIn)` against the latest block while supplying conservative maximum VOID approval and ETH value from a dedicated keeper wallet. Supply both limits so a same-block direction change cannot make the prepared call use the wrong asset. These are limits, not expected spend; the unnecessary asset is never pulled, and unused assets and swap output return atomically.
3. Execute promptly. The executor rereads the pool and curve inside the transaction, corrects the live price to the exact current graduation ratio, and calls permissionless `graduate()`.
4. Verify the excess-token burn, zero curve reserves, final LP NFT registration, locker ownership, 365-day unlock, and executor zero balances from events and direct reads.
5. If correction capital is unreasonable because a hostile pool has deep outside liquidity, do not graduate. Use the Safe's delayed adapter replacement process, seed that new target, and repeat the simulation.

During the 365-day LP lock, periodically repeat the Safe ERC-721 receiver staticcall used by the deployment script and alert on any fallback-handler change. The deployment check is a snapshot; Safe owners can change the handler later.

No deployment has been broadcast from this repository yet.

# Base Mainnet deployment runbook

VOIDCOIN supports Base Mainnet only. The application hard-codes chain ID `8453`; it ignores stale test-chain environment variables.

## Required decisions and deployed dependencies

Do not broadcast until all values are final and independently reviewed:

- `SAFE_ADDRESS` — deployed production Safe that will moderate metadata and own the curve.
- `INITIAL_TOKEN_URI` — permanent IPFS JSON for the supplied VOID logo and genesis identity.
- `BASE_MAINNET_RPC_URL` — production Base RPC.
- `BASESCAN_API_KEY` — source-verification credential.
- A funded deployment signer selected through Foundry's encrypted keystore (`--account`) or hardware-wallet (`--ledger` / `--trezor`) flow. Never place a raw private key in Vercel or repository environment files.

The deployment script is Base Mainnet-only. It hardcodes the owner-approved 2 ETH virtual reserve and 25 ETH buyer-funded graduation threshold, pins the official Uniswap v3 NonfungiblePositionManager at `0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1`, deploys the migration adapter and immutable 12-month position locker, refuses an EOA Safe, and refuses empty genesis metadata.

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

Verify the predicted addresses, 980M/20M allocation, direct Safe ownership, 1% buy/sell fee, 2 ETH virtual reserve, 25 ETH buyer-funded threshold, graduation-gated treasury vesting, migration adapter, 12-month LP locker, and paused rename state.

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

1. Record the launch, token, curve, vesting, migration-adapter, and position-locker addresses.
2. Confirm the Safe already owns both token and curve and the deployer has no protocol authority.
3. Confirm the 20M creator allocation cannot release before successful graduation and the LP NFT cannot release for 365 days after graduation.
4. Set Vercel `NEXT_PUBLIC_VOIDCOIN_ADDRESS` and `NEXT_PUBLIC_VOIDCOIN_DEPLOYMENT_BLOCK`.
5. Configure the production RPC, database, private Blob store, Pinata, Resend, Alchemy webhook, admin email, WalletConnect ID, and secrets.
6. Keep renaming paused until moderation, event indexing, email, and Safe calldata are verified against the live address.
7. Add a separate external Base trading link only after liquidity is live and independently verified.

No deployment has been broadcast from this repository yet.

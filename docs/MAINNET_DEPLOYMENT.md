# Base Mainnet deployment runbook

VOIDCOIN supports Base Mainnet only. The application hard-codes chain ID `8453`; it ignores stale test-chain environment variables.

## Required decisions and deployed dependencies

Do not broadcast until all values are final and independently reviewed:

- `SAFE_ADDRESS` — deployed production Safe that will moderate metadata and own the curve.
- `MIGRATION_TARGET` — reviewed Base contract that atomically creates or funds the intended post-graduation pool.
- `VIRTUAL_ETH_RESERVE` — starting curve parameter in wei; this controls initial price and slippage.
- `GRADUATION_THRESHOLD` — buyer-funded ETH threshold in wei.
- `INITIAL_TOKEN_URI` — permanent IPFS JSON for the supplied VOID logo and genesis identity.
- `BASE_MAINNET_RPC_URL` — production Base RPC.
- `BASESCAN_API_KEY` — source-verification credential.
- `DEPLOYER_PRIVATE_KEY` — deployment-only key supplied locally; never commit or enter it into Vercel.

The deployment script refuses EOAs for the Safe or migration target and refuses zero curve parameters or empty genesis metadata.

## Rehearse without broadcasting

Run the full script against a local Base Mainnet fork first:

```bash
anvil --fork-url "$BASE_MAINNET_RPC_URL"
forge script contracts/script/Deploy.s.sol:DeployVOIDCoin \
  --root contracts \
  --rpc-url http://127.0.0.1:8545 \
  -vvvv
```

Verify the predicted addresses, 900M/100M allocation, Safe pending ownership, curve parameters, and paused rename state.

## Broadcast and verify

This is an explicit Mainnet spending gate:

```bash
forge script contracts/script/Deploy.s.sol:DeployVOIDCoin \
  --root contracts \
  --rpc-url base_mainnet \
  --broadcast \
  --verify \
  -vvvv
```

After broadcast:

1. Record the launch, token, curve, vesting-wallet, and migration-target addresses.
2. Have the production Safe call `acceptOwnership()` on the token.
3. Confirm the deployer has no token or curve authority.
4. Set Vercel `NEXT_PUBLIC_VOIDCOIN_ADDRESS` and `NEXT_PUBLIC_VOIDCOIN_DEPLOYMENT_BLOCK`.
5. Configure the production RPC, database, private Blob store, Pinata, Resend, Alchemy webhook, admin email, WalletConnect ID, and secrets.
6. Keep renaming paused until moderation, event indexing, email, and Safe calldata are verified against the live address.
7. Add a separate external Base trading link only after liquidity is live and independently verified.

No deployment has been broadcast from this repository yet.

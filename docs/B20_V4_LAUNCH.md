# VOID V4: native B20 + Uniswap Launch Auction

This is the production plan for V4. The contracts and scripts in this repository prepare the token and website, but nothing in this document authorizes a broadcast, Safe transaction, auction launch, or controller unpause.

## What V4 guarantees

- Base-native B20 Asset token at 18 decimals.
- Exactly `1,000,000,000 VOID` minted once to the production Safe.
- Supply cap fixed at exactly `1,000,000,000 VOID`.
- No default admin, minter, pauser, unpauser, seizure, blocked-burn, or operator role.
- Only the paused `VOIDB20SkinController` receives `BURN_ROLE` and `METADATA_ROLE`.
- Contest burns call the native B20 `burn()` and reduce `totalSupply()`.
- Approved proposals update B20 `name()`, `symbol()`, and ERC-7572 `contractURI()` atomically.
- The Safe cannot bypass the contest and edit token metadata directly.
- Deployment does not create an auction and does not unpause the rename contest.

Base activated B20 on Base Mainnet on July 8, 2026. The implementation is pinned to `base/base-std` commit `fc13edf179415af235933953fb4537e263c8d1db`.

## Build and test

```sh
npm run contracts:build
forge test --root contracts --match-contract VOIDB20V4Test -vv
npm run verify
```

Stock Forge uses Base's reference mocks. Before mainnet, run the same suite with Base's official patched Foundry so
the tests execute the Rust precompiles in-process:

```sh
base-forge test --root contracts --match-contract VOIDB20V4Test -vv
```

The output must identify `LIVE PRECOMPILE mode`, with no skips. Also obtain a focused independent audit of:

- `contracts/src/VOIDB20SkinController.sol`
- `contracts/src/VOIDB20Bootstrapper.sol`
- `contracts/script/DeployB20V4.s.sol`

## Prepare immutable genesis metadata

Put only public/non-secret deployment values in `.env.local`:

```dotenv
DEPLOYER_ADDRESS=0x...
SAFE_ADDRESS=0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9
BASE_MAINNET_RPC_URL=https://...
VOID_B20_SALT=0x...64_hex_characters...
PINATA_JWT=...
```

Then:

```sh
npm run b20:predict
npm run b20:publish
```

Copy `metadataURI` from the ignored `assets/genesis/b20-published.json` receipt to `VOID_B20_CONTRACT_URI`, then run:

```sh
npm run b20:verify
npm run b20:surface:test
npm run b20:surface:verify
```

The first verification command fails if the deployer nonce, B20 salt, predicted token address, metadata address, or
contract URI changed. The offline harness exercises the verifier's allow and deny paths without depending on a public
gateway. The predeployment surface verifier independently re-derives the expected token from the configured deployer
nonce and salt, fetches the exact JSON and PNG through Pinata and ipfs.io, verifies that the returned bytes hash to the
advertised CIDs, and validates the Basecat-compatible B20 fields, full market links, PNG content, and a visible square
image of at least 512px. Any failure blocks deployment and market launch.

## Dry-run deployment only

```sh
cd contracts
forge script script/DeployB20V4.s.sol:DeployB20V4 \
  --rpc-url "$BASE_MAINNET_RPC_URL" \
  --sender "$DEPLOYER_ADDRESS" \
  -vvvv
```

Do not add `--broadcast` until deployment is separately authorized after the audit and live-precompile checks. A successful dry run must report:

- exact one-billion supply in the Safe;
- supply cap equals supply;
- controller owner is the Safe;
- controller is ready and still paused;
- no auction created and no Safe transaction executed.

## Deployment gate

When separately authorized, rerun `npm run b20:verify` immediately before broadcasting. Any pending deployer transaction changes the bootstrapper address and therefore the B20 address; republish metadata if it changes.

The deployment creates the B20 and controller atomically. There is no Zora `addOwner` step. Do not call `setRenamePaused(false)` yet.

After deployment, run the verifier again in postdeployment mode. This mode reads Base Mainnet and refuses to pass
unless the deployed token/controller relationship and the live token identity, decimals, supply, cap, and contract URI
match the publication receipt:

```sh
npm run b20:surface:verify -- --token 0xTOKEN --controller 0xCONTROLLER
```

## Website cutover

After the token and controller are deployed, independently verified, and read successfully from Base Mainnet, configure the production website:

```dotenv
NEXT_PUBLIC_VOID_B20_ADDRESS=0x...
NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS=0x...
NEXT_PUBLIC_VOID_SKIN_CONTROLLER_DEPLOYMENT_BLOCK=...
```

The app will then read B20 `contractURI()` instead of Zora `tokenURI()`. It continuously reads live name, symbol, image, supply, destroyed supply, record burn, active proposal, controller pause state, and DexScreener market data. Buying remains external: Base App is the primary header link, and the telemetry section links to Uniswap, Fomo, DexScreener, and BaseScan.

Apply `drizzle/0001_premoderate_before_burn.sql` before enabling rename intake. The public flow is intentionally two-stage:
the initial private submission does not approve or burn tokens; a moderator first approves the content and pins the
final IPFS metadata; only then can the burner sign the exact URI-bound commitment. The server verifies the emitted burn
event before exposing Safe approval calldata. Keep the controller paused until this workflow has passed a production
smoke test.

## Launch the market through Uniswap

Open the official [Uniswap Launch Auction](https://app.uniswap.org/liquidity/launch-auction) flow and choose **Use existing token**. Do not choose **Create new token**; that would create a different immutable token and discard V4's B20/controller design.

Connect the production Safe and import the verified B20 address. Use the same VOID logo, `https://voidcoin.fun`, and genesis description. The auction UI then asks for economic choices that must be explicitly approved before any Safe signature:

- number of VOID allocated to the auction;
- auction currency;
- duration and start time;
- floor price or valuation assumptions;
- percentage reserved for post-auction Uniswap v4 liquidity;
- proceeds recipient and leftover-token recipient;
- LP position recipient, price range, and fee tier;
- optional identity/verification requirements.

Review the exact generated contracts, allowances, calldata, recipients, and value in the Safe before signing. Launching an auction makes it discoverable in Uniswap, but the token becomes normally swappable only after the auction completes and its migration seeds the v4 pool. Confirm migration and claims before announcing ordinary trading.

## Metadata and discovery checklist

The B20 contract is the canonical identity source, but third-party apps still cache and enrich token data independently. After liquidity exists and at least one pool transaction has occurred:

1. Confirm `name()`, `symbol()`, `decimals()`, `totalSupply()`, `supplyCap()`, and `contractURI()` on Base Mainnet.
2. Fetch the IPFS JSON through two gateways; confirm the image is square, public, and has the correct MIME type.
3. Verify the controller and bootstrapper source on BaseScan. A native B20 has no ordinary Solidity bytecode to verify.
4. Complete BaseScan token ownership/profile update with the official logo, description, and website.
5. Open `https://base.app/coin/base-mainnet/TOKEN_ADDRESS` and record the displayed name, ticker, logo, market, and website.
6. Open `https://fomo.family/tokens/base/TOKEN_ADDRESS` and record the same fields.
7. Confirm the Uniswap token and auction/pool pages.
8. Confirm DexScreener discovers the highest-liquidity Base pair.
9. Submit identical data to the independent metadata providers those apps use if any cached field is missing.
10. Save screenshots, URLs, timestamps, and support tickets as launch evidence. No contract can force a third-party cache to refresh.

Only after the token, auction/pool, website, moderation path, and external metadata surfaces have passed the final checklist should the Safe separately call `setRenamePaused(false)`.

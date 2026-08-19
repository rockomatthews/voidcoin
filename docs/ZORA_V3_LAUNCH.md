# VOIDCOIN V3 — Zora-native launch

V3 retires the custom V1 bonding curve and V2 site router. The visible token is a standard Zora **Content Coin** on Base. Zora creates its native market and discovery page; `voidcoin.fun` links buyers directly to Zora and Base App. The separate `VOIDZoraSkinController` only handles competitive burns and approved identity changes.

No Mainnet broadcast is authorized by this document.

## Fixed production choices

- Base Mainnet (`8453`)
- Zora Content Coin, not Trend Coin
- one billion fixed supply under Zora's Content Coin implementation
- ETH market currency
- Zora `LOW` starting market-cap profile
- Safe is creator, payout recipient, and controller owner
- first record: 1,000,000 VOID
- takeover floor: greater of prior record +250,000 VOID or prior record +10%
- optional strategic premium: no more than 2,000,000 VOID above the live floor
- website moderation remains required before the controller applies name, symbol, and IPFS metadata

Zora's protocol allocation and fee behavior are accepted as protocol-level launch terms. V3 does not recreate the previous custom 98/2 token allocation.

## Production sequence

1. Obtain explicit approval to publish, then run `npm run genesis:zora:publish`. It publishes a clean Zora genesis image and metadata JSON containing the description and `https://voidcoin.fun`, but no false pre-launch contract address. Copy the resulting URI from `assets/genesis/zora-published.json` into `ZORA_GENESIS_URI`. Do not reuse V1/V2 metadata containing an obsolete contract address.
2. Install the isolated Zora launch tool:

   ```bash
   npm install --prefix tools/zora-launch
   ```

3. With `SAFE_ADDRESS` and `ZORA_GENESIS_URI` loaded, prepare—but do not broadcast—the Zora calldata:

   ```bash
   npm run calldata --prefix tools/zora-launch
   ```

   Review `tools/zora-launch/zora-launch-calldata.json`. Confirm chain `8453`, Safe creator/payout recipient, `ETH`, `LOW`, name `VOIDCOIN`, ticker `VOID`, and the expected IPFS URI. Import `tools/zora-launch/safe-transaction-builder.json` into Safe Transaction Builder; the first file is a verification receipt and is intentionally not importable by Safe.

   The generator validates the live metadata by default and sends the launch request to Zora's official `api-sdk.zora.engineering/create/content` endpoint with `startingMarketCap: LOW` explicitly present. This direct request is intentional: Coins SDK 0.8.0 declares the setting but currently omits it from the API request. `ZORA_SKIP_METADATA_VALIDATION=true` exists only for an offline/dummy test and must not be used for production calldata.
4. Execute the exact Zora creation call through the production Safe. Record the token, pool, block, and transaction hash. Verify the token page works at `https://zora.co/coin/base%3A<TOKEN>` and the token is visible in the Safe.
5. Set `ZORA_VOID_ADDRESS` to the deployed Content Coin and run the controller script first without `--broadcast`, then obtain a new explicit broadcast authorization. The script is pinned to the production token and Safe addresses, proves the Safe is already a Zora coin owner, and refuses any substitute 1B token or contract.
6. After the verified controller deploys, the Safe calls `addOwner(controller)` on the Zora coin. Confirm `isOwner(controller) == true`.
7. The Safe calls `setRenamePaused(false)` on the controller. The contract rejects this step unless it is already a Zora coin owner.
8. Configure Vercel Preview with `NEXT_PUBLIC_ZORA_VOID_ADDRESS`, `NEXT_PUBLIC_VOID_SKIN_CONTROLLER_ADDRESS`, and the controller deployment block.
9. Run the fresh-wallet acceptance test below. Only after it passes may Preview be promoted to Production.

## Fresh-wallet acceptance test

Use a wallet that has never held VOID.

1. Open the Zora coin URL from a clean browser session.
2. Buy a small amount with ETH and save the successful Base transaction hash.
3. Prove the ERC-20 `Transfer` log credits the fresh wallet and `balanceOf(freshWallet)` increases.
4. Confirm the balance appears on Zora and can be imported by contract address in the wallet. Base App discovery is an external indexing outcome and must be observed, not assumed.
5. Open `voidcoin.fun`; confirm the header, hero, title, image, ticker, market links, and balance reader use the same Zora token address.
6. Approve only the selected burn amount to the controller, submit the first competitive burn with its expected burn ID, and prove the Zora token's `totalSupply()` falls by exactly that amount. A stale prepared ID must revert before any token transfer.
7. Run a complete private proposal, moderator approval, Safe execution, and confirm the Zora token's actual `name()`, `symbol()`, and `tokenURI()` all change. Confirm the site and archive follow the same state.

Any missing balance, reverted purchase, incorrect recipient, mismatched metadata, or stale V1/V2 address is a launch stop.

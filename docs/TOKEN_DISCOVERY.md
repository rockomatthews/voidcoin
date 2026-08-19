# Token discovery and official links

VOIDCOIN's permanent official website is `https://voidcoin.fun`. Every genesis and approved-rename metadata document must retain that exact website even when the token name, symbol, and image change.

## What each app reads

- The token contract exposes an ERC-1046-style `tokenURI()` with the current name, symbol, image, description, website, Base App route, Fomo route, DexScreener route, and BaseScan contract route. This is the protocol-controlled source.
- Base App indexes token data through Coinbase asset-metadata services. Its documented Base token route is `https://base.app/coin/base-mainnet/TOKEN_ADDRESS`; do not assume it will render every custom `tokenURI()` field.
- Fomo renders `token.info.description` and `token.socialLinks.website` from its own backend. Its public client also uses Mobula market data and allows The Grid and Defined token-media sources. Keep Mobula, CoinGecko, The Grid, BaseScan, and DexScreener consistent with the official site.
- DexScreener automatically discovers a token after a liquidity pool exists and has at least one transaction. Its description and website are separately indexed from supported token-information sources or its paid Enhanced Token Info product.
- BaseScan shows a project description, website, and social links after source verification, address-ownership verification, and an approved Token Update request.

Onchain/IPFS metadata improves portability, but no immutable contract can force a third-party app to refresh or display a website field. Third-party caches must be verified after launch.

## Before deployment

1. Put the public gas-payer address in `DEPLOYER_ADDRESS`. Never put its private key in `.env.local`.
2. Run `npm run genesis:predict` and review every predicted address.
3. Run `npm run genesis:publish`. The publisher embeds the predicted VOID token address in all official routes and writes the final receipt to `assets/genesis/published.json`.
4. Copy the receipt's `metadataURI` into `INITIAL_TOKEN_URI`.
5. Immediately before the Foundry dry run and again before broadcast, run `npm run genesis:verify`. Any pending deployer transaction changes the nonce and invalidates the metadata; republish before proceeding.

## After deployment and liquidity

1. Confirm the deployed token address exactly matches the prediction recorded in `assets/genesis/published.json`.
2. Verify the contract source on BaseScan, verify address ownership, and submit a Token Update request with:
   - Website: `https://voidcoin.fun`
   - The neutral description from the genesis metadata
   - The approved VOID logo
3. Set `NEXT_PUBLIC_VOIDCOIN_ADDRESS` and `NEXT_PUBLIC_VOIDCOIN_DEPLOYMENT_BLOCK` in Vercel and deploy the already-tested artifact.
4. After the Uniswap pool is live and has a transaction, verify `https://dexscreener.com/base/TOKEN_ADDRESS`. Do not purchase DexScreener Enhanced Token Info without a separate spending approval.
5. Submit the asset to CoinGecko and make its website exactly `https://voidcoin.fun`.
6. Claim or submit the token profile through The Grid and Mobula, using the same website, description, contract address, and logo.
7. Verify `https://base.app/coin/base-mainnet/TOKEN_ADDRESS`. If the website is absent or wrong after indexing, send Coinbase/Base App support the verified BaseScan page and official domain.
8. Verify `https://fomo.family/tokens/8453/TOKEN_ADDRESS`. If the website is absent or wrong, send Fomo support the verified BaseScan, Mobula, and The Grid records.
9. Record screenshots and timestamps for Base App, Fomo, BaseScan, and DexScreener in the launch evidence.

## Contract-address link behavior

The Base App, Fomo, DexScreener, and BaseScan routes cannot be final until the token address is known. The deployment predictor derives that address from the public deployer address and its pending nonce. `genesis:verify` is therefore a mandatory broadcast gate, not an informational check.

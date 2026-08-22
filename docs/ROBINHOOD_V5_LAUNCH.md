# VOIDCOIN V5 — immediate Robinhood Chain launch

V5 puts public availability before mutable ERC-20 identity. It uses the live hood.dev launcher on Robinhood Chain
(chain `4663`) because one transaction creates the token, initializes a real Uniswap V3 pool, deposits the nominal
one-billion-token supply as single-sided liquidity, locks the LP position permanently, and indexes the launch. There is
no auction, minimum raise, graduation, or migration.

## What "on Robinhood" means

- Robinhood Chain is a permissionless EVM L2 supported by the separate Robinhood Wallet.
- Robinhood Wallet users can hold Robinhood Chain assets, connect to dapps, and use supported aggregator routes.
- Robinhood Chain is explicitly separate from Robinhood brokerage and Robinhood Crypto accounts.
- A hood.dev launch does **not** create a Robinhood brokerage listing. No permissionless launchpad can promise one.
- The guaranteed purchase surface at confirmation is hood.dev's own indexed trading terminal and the live Uniswap V3
  pool. Robinhood Wallet search and swap routing must be observed after launch, not assumed.

## Frozen V5 product boundary

| Requirement | V5 result |
| --- | --- |
| Public trading immediately | Yes. The pool exists in the launch transaction. |
| One-billion fixed supply | Nominally yes. The launcher requests `1,000,000,000e18`, then permanently burns the few wei Uniswap liquidity rounding cannot place. There is no mint function. |
| Permanent LP lock | Yes. The launch position cannot be withdrawn. |
| Logo, description, links | Published in launch calldata, ERC-7572 metadata, on-chain getters, and launch event. |
| Post-launch artwork/description/link changes | Yes, through the Hood ownership registry and V5 controller. |
| Permanent burn contest | Yes. The controller pulls and burns real HoodToken balances. |
| Mutable wallet-visible ERC-20 name/ticker | **No.** HoodToken constructor name and ticker are immutable. |
| Mutable site display name/ticker | Yes. The controller records the approved display identity. |
| Robinhood brokerage listing | No; that requires Robinhood's independent listing decision. |

The immutable `VOIDCOIN` / `VOID` ERC-20 identity is a deliberate compatibility concession. The controller changes the
artwork, description, socials, `contractURI`, and the display identity used by voidcoin.fun. Every public page must say
this plainly; it must never claim that wallets will adopt the display ticker.

The verified launcher source explicitly burns the residual token dust left by Uniswap's integer liquidity math. A live
fork at the frozen `-206000` tick requested `1,000,000,000e18` and settled at
`999999999999999999999998135` wei: 1,865 wei below nominal, or 0.000000000000001865 VOID. This is invisible at normal
display precision, but V5 records the post-launch total as the controller's baseline so it is not misreported as a
contest burn. The deployment gate rejects launch dust above 1,000,000 wei (0.000000000001 VOID).

## Production contracts and addresses

- Existing 2-of-3 Safe address: `0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9`
- HoodLauncher: `0x5e4121c262B846eb518EF3EADCD5566838AA841F`
- TokenOwnerRegistry: `0xEBbf66e306cE0Df652898A4894f6aBAF09F8Cd58`
- Uniswap V3 launch venue: `venueId = 1`
- Robinhood Chain explorer: `https://robinhoodchain.blockscout.com`

The Base Safe is not yet deployed on Robinhood Chain. Its original Safe v1.4.1 deployment can be replayed through the
same canonical factory to produce the exact same address and the same three owners with threshold two. The read-only
simulation is recorded by:

```sh
npm run hood:safe:prepare
```

This only prepares `tools/hood-launch/safe-replay-preparation.json`. Executing the contained EOA transaction is a
separate explicit gate.

## Launch preparation

First publish the final V5 genesis JSON based on `tools/hood-launch/genesis-metadata.template.json`. Publication is an
external, permanent action and requires its own authorization. Then configure:

```sh
VOID_HOOD_IMAGE_URI=ipfs://QmSTzmwHa3NiHhEb6EsztuvYkScVnmuts9HkFobpVbbuJu
VOID_HOOD_METADATA_URI=ipfs://FINAL_V5_METADATA_CID
VOID_HOOD_DESCRIPTION='VOIDCOIN is a Robinhood Chain token with immediately available locked Uniswap liquidity. Holders can permanently burn VOID to compete for the community-controlled display identity, artwork, description, and links. The ERC-20 name and ticker remain VOIDCOIN and VOID.'
VOID_HOOD_SOCIALS='{"website":"https://voidcoin.fun"}'
VOID_HOOD_START_TICK=-206000
```

`-206000` is a review starting point, not a frozen economic decision. At the live 2026-08-22 launcher bounds it implies
approximately 1.13235 ETH initial FDV, safely above the live 1.11 ETH minimum. The preparation script rereads the fee,
FDV bounds, supply bounds, venue registration, Safe code, and predicted address immediately before it writes calldata:

```sh
npm run hood:launch:prepare
```

Outputs:

- `tools/hood-launch/launch-preparation.json` — human-review receipt;
- `tools/hood-launch/safe-launch.json` — one Safe transaction calling `HoodLauncher.launch`.

The launch contains no dev buy. Buyers can trade after confirmation through the launchpad market. The optional sniper
guard remains enabled and caps non-exempt wallets at 2% for the launcher's snapshotted restriction window.

The no-broadcast live fork gate is:

```sh
RUN_HOOD_LIVE_GATE=true \
ROBINHOOD_MAINNET_RPC_URL=https://rpc.mainnet.chain.robinhood.com \
forge test --root contracts --match-contract VOIDHoodV5ForkTest -vv
```

It launches through the live HoodLauncher on forked state, verifies the predicted token and live Uniswap V3 pool,
checks the nominal supply/dust bound and all metadata getters, deploys the controller, transfers registry ownership,
and proves the controller remains paused. It never broadcasts.

## Controller sequence

The controller is deliberately separate from launch so a controller defect cannot prevent the market from opening.

1. Launch the token from the Robinhood-chain Safe. Record token, pool, position, and transaction addresses.
2. Confirm the Hood board shows the correct logo, description, links, token address, supply, and live buy/sell controls.
3. Deploy `VOIDHoodSkinController` with `DeployHoodV5Controller.s.sol`. It starts paused and cannot edit the token yet.
4. Run `npm run hood:controller:handoff` to prepare the single Safe ownership-registry call.
5. Execute the handoff only after independent review. Confirm `controllerReady() == true` and all metadata is unchanged.
6. Deploy the V5 website configuration and verify chain state, Blockscout, DexScreener, Hood, and Robinhood Wallet.
7. Unpausing the contest remains a final, separate Safe action after the full moderation path is rehearsed.

Required production environment after deployment:

```sh
NEXT_PUBLIC_VOID_HOOD_TOKEN=0x...
NEXT_PUBLIC_VOID_HOOD_CONTROLLER=0x...
NEXT_PUBLIC_VOID_SKIN_CONTROLLER_DEPLOYMENT_BLOCK=...
ROBINHOOD_MAINNET_RPC_URL=https://...
```

## V4 failure recovery remains separate

The Base V4 auction ended without graduation. It must not be migrated. Buyers claim refunds through the auction
interface, while the Safe may separately recover the failed auction's deposited token supply by calling
`sweepUnsoldTokens()` from the configured `tokensRecipient`. V4 recovery, V5 Safe creation, V5 metadata publication,
V5 launch, V5 controller deployment, token-control handoff, website cutover, and controller unpause are independent
authorization gates.

## Pre-public-launch audit boundary

Before controller ownership handoff or contest unpause, independently review:

- `contracts/src/VOIDHoodSkinController.sol`;
- `contracts/test/VOIDHoodSkinController.t.sol`;
- `contracts/test/VOIDHoodV5.fork.t.sol`;
- `contracts/script/DeployHoodV5Controller.s.sol`;
- both Hood preparation scripts and generated calldata;
- the V5 commitment encoder and moderator calldata path;
- live Robinhood Chain launcher, registry, token bytecode, pool, and ownership reads;
- the explicit immutable-name/ticker disclosure on every user-facing surface.

The Hood launcher and its third-party indexer remain external dependencies. Verified source and passing local tests do
not guarantee uninterrupted launchpad UI availability, Robinhood Wallet routing, or Robinhood brokerage support.

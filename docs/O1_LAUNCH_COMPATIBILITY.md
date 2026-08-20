# VOIDCOIN V4 — o1 Launchpad compatibility gate

Status: **blocked on an o1 launch-factory capability; do not audit or deploy yet**

Checked: August 20, 2026

## Product priorities

1. Launch through the canonical o1 Launchpad path used by well-presented Base tokens so VOID receives the same B20, o1 profile/indexer, permanent Uniswap v4 market, and downstream discovery path.
2. Preserve VOID's one-billion fixed supply, genuine supply-reducing rename burns, mutable name/symbol/logo/profile, commitment-bound Safe approval, paused-at-launch controller, and live website monitoring.

## What the current o1 Base route satisfies

The active o1 Base route creates a native B20 Asset and a Uniswap v4 market in one transaction. Current documented defaults include:

- exactly 1,000,000,000 tokens at 18 decimals;
- an adminless, non-mintable B20;
- an IPFS-backed public profile with image, description, website, X, Telegram, and extra metadata;
- optional post-launch updates to name, symbol, `contractURI`, and extra metadata;
- permanent token-side Uniswap v4 liquidity;
- an o1 token page, public indexer/API, trading surface, creator fee accounting, and announcements; and
- Base ETH or USDC pairing.

Primary references:

- <https://docs.o1.exchange/launchpad/introduction>
- <https://docs.o1.exchange/launchpad/create/token-creation>
- <https://docs.o1.exchange/launchpad/architecture/contracts>
- <https://docs.o1.exchange/launchpad/integration/direct>
- <https://docs.o1.exchange/launchpad/reference/production-contracts>
- <https://docs.o1.exchange/launchpad-api-openapi.yaml>

Active Base crypto factory checked:

- `B20LaunchpadFactory`: `0xa52ad458cE0282a971ecC71C051A32f28946bb9F`
- verified source: <https://sourcify.dev/server/v2/contract/8453/0xa52ad458cE0282a971ecC71C051A32f28946bb9F?fields=all>

## Confirmed incompatibility

The current o1 factory cannot create the required burn-enabled token.

Its verified `B20LaunchpadFactory` source:

1. accepts only `roleMode` 0 or 1;
2. grants only `METADATA_ROLE` when `roleMode == 1`;
3. does not expose arbitrary B20 initialization calls or an existing-token registration route;
4. creates the B20 with `initialAdmin = address(0)`;
5. explicitly treats `BURN_ROLE` as a dangerous role in its post-launch immutability assertion; and
6. cannot add a burn role after launch because the token has no default admin.

The public API independently states that editable metadata grants no mint, burn, pause, operator, or ownership power.

Therefore:

- launching from the Safe with editable metadata gives the Safe a direct metadata bypass and no burn authority;
- launching through a custom VOID controller can make that controller the metadata authority, preserving commitment-bound metadata updates;
- but `token.burn(...)` from that controller still reverts because it has no `BURN_ROLE`; and
- sending tokens to a dead address would not reduce native B20 `totalSupply()` and is not an acceptable substitute for VOID's genuine burn mechanic.

This is a protocol-level incompatibility, not a website or deployment-script issue.

## Required o1 capability

VOID needs an o1-recognized launch route that adds one narrowly scoped initialization mode:

```text
roleMode = CONTROLLER_METADATA_AND_BURN
controller = predicted/deployed VOIDB20SkinController

grant METADATA_ROLE to controller
grant BURN_ROLE to controller
grant no DEFAULT_ADMIN_ROLE
grant no MINT_ROLE
grant no BURN_BLOCKED_ROLE
grant no PAUSE_ROLE or UNPAUSE_ROLE
grant no OPERATOR_ROLE or SEIZE_ROLE
```

The factory must then assert the controller is the only intended holder of metadata and burn authority and that the creator, launch factory, launch hook, vesting vault, treasury, and allocation recipients hold no dangerous role.

Acceptable o1 solutions:

1. a new allowlisted `roleMode` in an o1 production factory;
2. a supported controller address/role bundle in `LaunchParams`; or
3. an o1-indexed existing-B20 registration path that verifies the same supply, role, metadata, and liquidity invariants before opening the canonical market.

A private fork of the o1 contracts is not sufficient. It would not automatically receive the canonical o1 profile/indexing path that is the primary reason for this pivot.

## Exact request to send o1

> We want to launch VOIDCOIN through the canonical o1 Base B20 launch path, with the standard one-billion fixed supply, o1 profile/indexing, and permanently locked Uniswap v4 liquidity. VOID has one additional non-custodial feature: holders compete by transferring tokens to a controller that permanently burns them, and the winning burn commitment can update the B20 name, symbol, and contractURI only after Safe approval. The B20 must remain adminless and non-mintable.
>
> Your current verified `B20LaunchpadFactory` accepts only roleMode 0/1, grants only METADATA_ROLE, rejects BURN_ROLE as dangerous, and leaves no admin capable of granting it later. Can o1 support a production launch mode or allowlisted controller parameter that grants exactly METADATA_ROLE and BURN_ROLE to our audited controller during B20 initialization, while granting no admin, mint, pause, seize, operator, or blocked-burn role? The launch must remain a canonical o1 launch in your indexer/UI and downstream Base discovery path. An existing-token registration route with the same verified invariants would also work.
>
> We will provide the controller source, audit report, deterministic address, role invariants, and a no-broadcast Base simulation. We will not launch until you confirm the exact production factory/API route and indexing treatment.

## Work that remains reusable

The existing `VOIDB20SkinController` state machine remains the intended authority model. Its contest logic, stale-ID protection, commitment binding, burn accounting, metadata validation, Safe ownership, initial pause, website reads, and monitoring components remain reusable.

The existing `VOIDB20Bootstrapper` and `DeployB20V4.s.sol` are not the production launch path if o1 supports the requested mode. They would be replaced by an o1-specific controller-launch adapter and a Safe transaction preparation/verification flow using the exact active o1 factory ABI and configuration.

## Closed gates

Until o1 confirms a supported production route:

- do not pay for the frozen V4 audit;
- do not deploy the custom bootstrapper or controller;
- do not publish final-address metadata;
- do not prepare or sign an o1 launch transaction;
- do not create a Uniswap auction or pool separately; and
- do not describe VOID V4 as ready to launch.

Once o1 confirms support, freeze the exact o1 factory/API version, implement the adapter, run the full local suite and a live-precompile no-broadcast simulation, and issue a replacement auditor package covering the actual o1 path.

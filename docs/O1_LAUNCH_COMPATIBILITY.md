# VOIDCOIN V4 — o1 Launchpad compatibility gate

Status: **o1 rejected for VOID V4; custom native B20 route selected**

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

## Why no undocumented o1 route remains

The public API does not provide an escape hatch around the factory. Its launch preparation endpoint builds the
active factory call, while its indexer documentation states that public clients cannot write product records or
force an indexing job. An API key therefore changes access to documented preparation endpoints, not the token roles
the production factory can grant.

Flaunch's external-token importer was also evaluated as a fallback. Its production `TokenImporter` requires an
owner-approved verifier to accept the token/caller, and its `AnyPositionManager` accepts launches only from approved
coin creators. It is not a permissionless route for a custom VOID B20 and would merely replace an o1 dependency with
a Flaunch approval dependency.

References:

- <https://docs.o1.exchange/launchpad/api/introduction>
- <https://docs.o1.exchange/launchpad/api/launches>
- <https://docs.o1.exchange/launchpad/architecture/frontend-indexer>
- <https://github.com/flayerlabs/flaunch-sdk>
- <https://github.com/flayerlabs/flaunchgg-contracts>

## Capability o1 would have needed

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

## Selected self-service route

The existing `VOIDB20SkinController` state machine remains the intended authority model. Its contest logic, stale-ID protection, commitment binding, burn accounting, metadata validation, Safe ownership, initial pause, website reads, and monitoring components remain reusable.

The production route is now:

1. create VOID through Base's native B20 factory using the audited `VOIDB20Bootstrapper`;
2. grant only `BURN_ROLE` and `METADATA_ROLE` to the paused controller during atomic initialization;
3. publish ERC-7572/IPFS metadata using the same top-level B20 fields and `links.website` shape observed on
   well-rendered o1 launches, while truthfully identifying VOIDCOIN rather than o1 as the launch source;
4. block market launch unless the metadata JSON and square PNG resolve through two independent public IPFS gateways;
5. use Uniswap's existing-token launch flow to create the public liquid market without replacing the token; and
6. verify Base App, Fomo, Uniswap, DexScreener, BaseScan, and the VOID website before separately unpausing the contest.

Base officially documents direct custom B20 creation with arbitrary initialization calls. This preserves VOID's
roles and one-billion cap without a launcher allowlist: <https://docs.base.org/get-started/launch-b20-token>.

## Closed gates

This decision does not authorize deployment, metadata publication, approval, auction/pool creation, Safe execution,
or controller unpause. The contract audit, final-address metadata checks, and launch economics remain explicit gates.

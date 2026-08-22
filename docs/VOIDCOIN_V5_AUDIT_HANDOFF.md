# VOIDCOIN V5 audit handoff

## Frozen review target

- Repository: `/Users/rob/Desktop/voidcoin`
- Branch: `codex/robinhood-v5`
- Production freeze: `fa6148fd1489fc5b3e2f9cf87cfd3b45b85cb624`
- Parent: `7ccae32409d416008d1cf295cd19c623c5a75a16`
- Review diff: `git diff 7ccae32409d416008d1cf295cd19c623c5a75a16..fa6148fd1489fc5b3e2f9cf87cfd3b45b85cb624`
- Deployment state: nothing in V5 has been published, signed, broadcast, deployed, handed off, or unpaused.

The audit target is the frozen commit, not the branch tip. This handoff file is intentionally delivered after the
production freeze and is not part of the reviewed bytecode.

## Product and trust boundary

V5 launches through hood.dev's live `HoodLauncher` on Robinhood Chain (`4663`), venue `1` (Uniswap V3). One launch
transaction deploys an immutable-name/symbol `HoodToken`, creates its WETH pool, provides single-sided token liquidity,
locks the LP position permanently, and registers the creator in hood.dev's ownership registry. There is no auction,
graduation, or migration.

Production dependencies:

- HoodLauncher: `0x5e4121c262B846eb518EF3EADCD5566838AA841F`
- TokenOwnerRegistry: `0xEBbf66e306cE0Df652898A4894f6aBAF09F8Cd58`
- intended 2-of-3 Safe: `0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9`
- public RPC used for the live fork: `https://rpc.mainnet.chain.robinhood.com`
- explorer: `https://robinhoodchain.blockscout.com`

The launchpad and its indexer are external dependencies and are not claimed to be audited by this engagement. Please
review their verified live bytecode/source wherever a V5 safety property depends on it.

## Required conclusions

Please explicitly conclude on each of these points:

1. `VOIDHoodSkinController` can only burn tokens actually supplied by the challenger and a successful burn reduces
   `totalSupply()` exactly once.
2. The expected burn id, chain id, controller address, burner, amount, every mutable metadata field, display identity,
   and salt are commitment-bound without an ambiguous encoding or replay path.
3. Approval either updates image, description, socials, contract URI, and display identity atomically or rolls back the
   slot and all metadata.
4. A stale id, takeover, lock, expiry, pause, failed token call, or reentrancy attempt cannot move tokens or corrupt a
   newer slot.
5. The controller begins paused, cannot unpause before registry handoff, cannot renounce ownership, and can return token
   control only while paused with no active slot.
6. hood.dev's immutable ERC-20 `name()` and `symbol()` remain `VOIDCOIN` and `VOID`; the controller changes only the
   website display identity and HoodToken's mutable metadata getters. Confirm the UI never represents otherwise.
7. The moderator path constructs the exact Solidity commitment and freezes the complete Safe `approveRename` calldata
   only after the final metadata has been published.
8. Every API path fails closed on a missing, malformed, wrong-chain, or mismatched token/controller configuration.
9. The Safe replay transaction really creates the same v1.4.1 2-of-3 Safe at the intended address on Robinhood Chain,
   and no launch can be prepared until that Safe has code.
10. Launch and handoff preparation validate live addresses, ownership, supply, launch fee, FDV/supply bounds, venue,
    predicted address, paused state, controller wiring, and post-launch supply baseline immediately before calldata is
    emitted.
11. The logo, description, socials, contract URI, launch event, hood.dev route, explorer route, DexScreener route, and
    website rendering give indexers the maximum available discovery surface without promising Robinhood brokerage
    listing or automatic wallet routing.

## Supply-rounding fact to reproduce

The verified HoodLauncher intentionally burns the few token wei that Uniswap V3 integer liquidity math cannot place.
At `tickIfToken0IsNewToken = -206000`, the live fork requested `1,000,000,000e18` and observed:

```text
requested supply: 1000000000000000000000000000
settled supply:   999999999999999999999998135
launch dust:      1865 wei of VOID
```

The controller records settled supply as `launchSupply`, so this protocol dust is not counted as a contest burn. Both
deployment and handoff gates reject a supply above nominal or more than 1,000,000 wei below nominal. Please assess the
bound and confirm there is no mint path.

## Reproduction commands and observed results

```sh
forge fmt --root contracts --check
forge test --root contracts --no-match-contract VOIDCOINV4LiveGateTest
npm test
npm run lint
npm run build
npm run contracts:security
npm audit --omit=dev
RUN_HOOD_LIVE_GATE=true \
ROBINHOOD_MAINNET_RPC_URL=https://rpc.mainnet.chain.robinhood.com \
forge test --root contracts --match-contract VOIDHoodV5ForkTest -vv
```

Observed on 2026-08-22:

- stock Forge: 174 passed, 0 failed, 10 skipped;
- V5 live Robinhood fork: 1 passed, 0 failed;
- app: 27 passed, 0 failed;
- ESLint: passed;
- Next.js 16.3.0 production build: passed;
- Slither: 0 findings across all 11 production targets;
- `npm audit --omit=dev`: 0 vulnerabilities.

The excluded `VOIDCOINV4LiveGateTest` is an intentional Base-native-precompile gate for V4 and is unrelated to V5.
The ten stock-suite skips are opt-in network/fork tests, including the separately executed V5 live gate.

## Frozen SHA-256 manifest

```text
393fcd0242f7058156e59c013ec7ca4478bad4c03f59cf717bf3016515fb1f32  contracts/script/DeployHoodV5Controller.s.sol
40303499268284b66875355387e38ee0c21e5e4856a3c383b06b91fd636f3cb1  contracts/src/VOIDHoodSkinController.sol
f8d30e04ce98974b5a862680869be292cb2bd5070bd859315976d290db8c0634  contracts/test/VOIDHoodSkinController.t.sol
c3c3ea6620604278cf4cb132dac0a914aecfbfdbe415201c1a05f47d643162a8  contracts/test/VOIDHoodV5.fork.t.sol
ef5ee8f857e367a68fed5cea81832d251b8b3ae714f4dab80ae5c67cbb11089f  docs/ROBINHOOD_V5_LAUNCH.md
59792e47651cd09e228d3f16c53644a22c7d009b57b4d5eef9f8e83772e90d7c  package.json
8246d2485188e89d86767220024e8faeb8cf233efc6c46bbb6a4ca7767264838  scripts/security-check.sh
7c53a42c956056e28647bdea39d6836e23f8d42b7d13e170995fd1795fca3151  src/app/api/admin/requests/[id]/route.ts
c02612019375b789fb2cb1fa6b9a136a07d02d121ab58c5f7553ad35cf02f494  src/app/api/market/route.ts
a7819815ce0b44d9ffe3f689bdfc0e4a9b83f510dde0a95697d5af2d52efd755  src/app/api/state/route.ts
842be6f68d607c7fcd13cdd9725501b9ecd9f3f020075214a4b6cfea828d424f  src/app/page.tsx
fdc9299388224016ff6fc830dc1a922e5149ce88e251a2fb63ae3fe7b10b5ffe  src/components/dynamic-identity-hero.tsx
f8d13db9b32d444ca0098aaa2a2a1117f65d0e3f4857b7907ba028dad2c3200c  src/components/protocol-stats.tsx
700026c886c63e14dc3a4d2e49fb2c2d1e4f19d21b395886395d1f34b6edd4c3  src/components/providers.tsx
b4ddcb10dbd446544be115087738967df3d30137085a80223575e01a1b2ae7a2  src/lib/chain.ts
1565613236bfe30c981dd35b1886844a84fc9a2fee337d28c13f6885aea91b22  src/lib/contract.test.ts
7da08021e17eb0daa9bf9ba7565c77649a24984330e6efce48b74cc6ffbf77db  src/lib/contract.ts
0f9e577282bc8e415153d1264e067b216cf4bb7db4c8dba9063573ba4c775369  src/lib/pinata.ts
170e109d65ad941e7a5536d9162d10ab4a8e5196ceb8e71e782236252f021541  src/lib/proposal.test.ts
b02d6ab146ddf727a6dff668ba23d9a55e9bd92197184be429eab956c5f72e56  src/lib/proposal.ts
209e9a2a7eb5d89912a86d2c21061cad6ac72064a714410b4f15944563a015dd  src/lib/token-metadata.test.ts
4c5cc5ef70e72a9485631f385f061baff65d6b7f7420dbddc5e0c3e4ee21aae2  src/lib/token-metadata.ts
3d2dd385955d841f4c9d136182fa3a9be177e18fc3381ca0e2a57378e8cad5e6  tools/hood-launch/genesis-metadata.template.json
97d21b8fb7961373931b7613aea80bc371452ba6d12d46947101e3ead5672f00  tools/hood-launch/prepare-controller-handoff.mjs
b9a3ec95d98adcceb41164b56e28c6d08a095d0f4a897e1f1339fd6302c26ffa  tools/hood-launch/prepare-safe-replay.mjs
c6a6af545832b46fa89f4132f1ffb2f293656e7e27a615bccb074570139471fb  tools/hood-launch/prepare.mjs
c628f3f5f9157f6b73eb5c41f2956ff2c0a506b4e21ee53b571e684b232c93c0  tools/hood-launch/safe-replay-preparation.json
```

## Launch gates after a clean audit

Keep these as separate authorizations and transactions:

1. deploy/replay the Robinhood-chain Safe;
2. publish and gateway-verify final V5 image and metadata;
3. prepare, inspect, sign, and execute the single hood.dev launch transaction;
4. visually and on-chain verify hood.dev, pool trading, image, links, token, pool, position, supply, and ownership;
5. deploy and source-verify the paused controller;
6. transfer Hood token ownership to the controller;
7. cut over and visually verify the website;
8. rehearse the full moderated proposal flow, then separately unpause the contest.

No clean audit authorizes any of these actions by itself.

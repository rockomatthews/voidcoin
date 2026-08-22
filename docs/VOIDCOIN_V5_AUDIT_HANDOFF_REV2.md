# VOIDCOIN V5 remediation retest handoff

## Frozen review target

- Repository: `/Users/rob/Desktop/voidcoin`
- Branch: `codex/robinhood-v5`
- Remediation freeze: `05eb5c17b66a7a96adc1ee666ab1fc6a9635b271`
- Prior audited freeze: `fa6148fd1489fc5b3e2f9cf87cfd3b45b85cb624`
- Review diff: `git diff fa6148fd1489fc5b3e2f9cf87cfd3b45b85cb624..05eb5c17b66a7a96adc1ee666ab1fc6a9635b271`
- Deployment state: no V5 metadata was published and no V5 Safe transaction, launch, controller deployment, handoff, or unpause occurred.

This file is a post-freeze delivery artifact. Review production code at the remediation freeze, not the later handoff-only commit.

## Requested retest conclusions

### H-1: public display identity versus immutable token identity

The burn form now labels both inputs `DISPLAY ... — SITE/PROFILE ONLY` and states before the separate burn transaction
that wallets and exchanges always show `VOIDCOIN (VOID)`. `/api/state` returns separate `name`/`symbol` display fields
and `immutableName`/`immutableSymbol` token fields. The hero, nav, metadata title/description, current-identity panel,
burn amounts, statistics, and footer render both identities without substituting the display ticker for the token unit.

Please confirm that no public V5 page represents the mutable display symbol as the ERC-20 ticker.

### M-1: lock front-run

`lockRenameSlot(uint256,bytes32)` now checks both the burn ID and the exact commitment reviewed by the Safe. The
moderator route encodes both values. `testLockBindsTheCommitmentTheSafeReviewed` proves a burner replacement makes the
queued lock revert, while a lock containing the current commitment succeeds.

### M-2: emergency-control disclosure

The burn acknowledgment and public trust disclosure now say the Safe can pause and permanently end the contest only
with no active slot, that earlier burns remain destroyed, and that there is no refund.

### M-3: live launch semantics

The live Robinhood fork now:

- executes a real `HoodToken.burn()` through the controller and checks `totalSupply()` and `contestBurned()`;
- asserts the live Uniswap position manager and FeeLocker bytecode hashes;
- asserts `ownerOf(positionId)` is the reviewed permanent FeeLocker;
- uses `voidcoin.fun`, not the stale `.wtf` domain.

The FeeLocker no-withdraw property still depends on review of its verified live source. The fork proves the position is
owned by that exact bytecode, not merely that a nonzero position ID was returned.

### M-4: genesis image and metadata readiness

The address/metadata circular dependency is resolved without a mutable gateway. `publish-hood-bootstrap.mjs` pins the
logo and bootstrap CID. A prediction-only preparation emits no executable Safe transactions. `publish-hood-final.mjs`
then pins address-bound metadata containing the exact Fomo route. The final preparation emits one two-call Safe batch:

1. `HoodLauncher.launch(bootstrapMetadataURI)`;
2. `HoodToken.setContractURI(finalAddressBoundMetadataURI)` on the predicted token.

`verify-hood-surface-readiness.mjs` requires both calls in that order, exact metadata schema/routes, CID-valid bytes
from Pinata and ipfs.io, PNG byte type, square dimensions of at least 512px, nonblank image entropy, and postdeployment
chain equality when `--token` and `--controller` are supplied. Because the calls are one Safe MultiSend, indexers cannot
observe an intervening confirmed block with bootstrap metadata.

The primary purchase route is now exactly `https://fomo.family/tokens/robinhood/<TOKEN_ADDRESS>`. hood.dev remains a
secondary terminal because its live site does not expose a working address-specific path; the receipt tells buyers to
paste the contract into hood.dev search.

### M-5 and M-6: launch guard semantics

The script now describes the Hood tick as normalized and uses `1.0001^tick × supply`, matching hood.dev's documented
launcher semantics. Supply bounds are compared in returned base units, without multiplying them by `1e18`. The live
HoodLauncher and TokenOwnerRegistry bytecode hashes are pinned and fail closed on change.

### Remaining Low findings

- `contestBurned` is returned by `/api/state` and has a dedicated public statistics tile.
- stale Base/B20 transaction copy is chain-neutral.
- gallery transaction links select Robinhood Blockscout in V5.
- Robinhood Wallet is labeled `WALLET HELP`, not a market venue.
- the generic hood.dev homepage is no longer the primary buy CTA; Fomo is address-specific and primary.
- the controller deploy script hardcodes the production Safe.
- genesis copy no longer claims locked liquidity before the live launch proof.
- controller socials are restricted on chain to compact JSON objects containing HTTPS string links only; malformed JSON,
  loopback HTTP, and `javascript:` values are rejected.

## Live dependencies pinned by remediation

```text
HoodLauncher               0xbe8f598c66a8a559faef2a6aea9b79273de6b439ba2d47e3b6af35c8364042c9
TokenOwnerRegistry         0xd106a4c613f6c254c316010ff7169ab308f6a669ed5a5d9a42bc449c8866b265
SafeProxyFactory           0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317
Safe singleton             0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4
SafeToL2Setup              0x2f25df28caf984366ee584e13241707e85dcd5a6ea0c14267928dafc1fd6274b
CompatibilityFallback      0x7c6007a5d711cea8dfd5d91f5940ec29c7f200fe511eb1fc1397b367af3c42f9
SafeL2 singleton           0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff
Uniswap position manager   0x0a493d1af3d0f25fed8efa205244ebee14114267a08647fc38c515c7cd6ead4f
Uniswap FeeLocker          0x87d9b76a9c1971c080e42a5cd9e74ee8012243bad5576af39f48e927131b6542
```

## Reproduction and observed results

```sh
forge fmt --root contracts --check
forge test --root contracts --no-match-contract VOIDCOINV4LiveGateTest
npm run verify
npm run contracts:security
npm audit --omit=dev
npm run hood:safe:prepare
RUN_HOOD_LIVE_GATE=true ROBINHOOD_MAINNET_RPC_URL=https://rpc.mainnet.chain.robinhood.com \
  forge test --root contracts --match-contract VOIDHoodV5ForkTest -vv
```

Observed on 2026-08-22:

- Forge excluding the unrelated Base-native V4 live-precompile gate: 176 passed, 0 failed, 10 skipped;
- live Robinhood fork: 1 passed, 0 failed; launch dust remained 1,865 wei;
- app tests: 27 passed, 0 failed;
- inherited offline gateway verifier harness: 40 scenarios, 0 deviations;
- ESLint, Next.js production build, and `forge fmt --check`: passed;
- Slither: 0 findings across all 12 production targets;
- production dependency audit: 0 vulnerabilities;
- Safe replay: exact Safe address reproduced and all five dependency hashes matched;
- browser verification: no error overlay, meaningful content rendered, and both Fomo CTAs resolved to the exact
  `/tokens/robinhood/<address>` route.

The Hood surface verifier itself requires real published CIDs and intentionally cannot be exercised until metadata
publication is separately authorized. Its byte/CID/image implementation is the same exported verifier exercised by the
40-scenario offline harness; the Hood-specific schema and two-call batch assertions are new review scope.

## SHA-256 manifest

```text
782429a83858d3d0d8d4ff584b2b197c598ab844a3c1269f0908969a2b8a13de  contracts/script/DeployHoodV5Controller.s.sol
8982c4b059590c38a37bce3f57c8dfa70c9a443931a4bf3d1df8262759dec505  contracts/src/VOIDHoodSkinController.sol
faa4b715d286601c9f61daa0fbcbc84afde7fd56346093e79ba131d797fca89e  contracts/test/VOIDHoodSkinController.t.sol
e6e32a863c16b1ee272fef666d69627f6940cc98c68656a5adcba3e04763b282  contracts/test/VOIDHoodV5.fork.t.sol
b74477541601758fc2377194941bf79ab82c968c3b1c264f9a8a06fded344f1e  docs/ROBINHOOD_V5_LAUNCH.md
ec5869cc10a1b5b6bfa0d6be54c3c19c807e40a6713242840ae20b7a947852bc  package.json
b23fa61e024d91d39458344fea0e03ad27c62abbd980bd213b7211d28ce24122  scripts/publish-hood-bootstrap.mjs
1fa88923387bbaa14d266d04a4253111d0f22bd43adc48c2b795ec78687e519e  scripts/publish-hood-final.mjs
3dab3c595a85117add5d7d9bd4296c60f0f076d1eb80b407fadb15d9cdd24ab2  scripts/verify-b20-surface-readiness.mjs
cb839b0fdf7745d0665d5ff448ec192c2fcf69277643aad15019a3b265ccedd6  scripts/verify-hood-surface-readiness.mjs
8246d2485188e89d86767220024e8faeb8cf233efc6c46bbb6a4ca7767264838  scripts/security-check.sh
9918f94570ebab57eb319ef8af4aa0950ec4078af36b87980435baf58a31829d  src/app/api/admin/requests/[id]/route.ts
d06fb5f48753d5e52bae4e2d9f9dada5f3e534aea9282951fe0a9c6c2ccb1fb1  src/app/api/state/route.ts
2717d34f705a5b87500ea05254201b0ed142f23857ef625cd48fc53fbfde2aa3  src/app/globals.css
5d1e51e766b6ceb21802ac8e2f919bb3a8b92d56c69e29c15a1a4aed1d277fab  src/app/layout.tsx
467dfe4ef89767c8b3d9f1c39a979693c105160529dd7f4291267b9f27d995f0  src/app/page.tsx
b36ce2aa815f3e132f0c88fc6b31afa3946df0e12ad2a0a878aabd8cd5edf781  src/components/burn-terminal.tsx
7242b75b67ca230815a76aff23abf91a6a44e34db7e3d67ad7cada32f3469694  src/components/dynamic-identity-hero.tsx
9b043fbd77fd916a6ecd90f77b15f85d1dc3ae6ef48ad10bec395ec879c129cc  src/components/identity-gallery.tsx
f9640c4f044634d592b9fdb9e3bf34276b73cd688c972fffb67a8111752dc834  src/components/protocol-stats.tsx
fe7ba953bd283e58e61ffb6fc8b995359f86cef52b48d791f05c1dc84f809b14  src/lib/contract.ts
0f9e577282bc8e415153d1264e067b216cf4bb7db4c8dba9063573ba4c775369  src/lib/pinata.ts
b02d6ab146ddf727a6dff668ba23d9a55e9bd92197184be429eab956c5f72e56  src/lib/proposal.ts
7ea124c3f18d96a2619dac06f4104a7c0c3aeeff9ea1a0cc759a833d19249afd  src/lib/token-metadata.test.ts
cbd8945975691f2a9b16661e8d4641aa9b60bab265a779c86b428056c57ec815  src/lib/token-metadata.ts
3d2dd385955d841f4c9d136182fa3a9be177e18fc3381ca0e2a57378e8cad5e6  tools/hood-launch/genesis-metadata.template.json
97d21b8fb7961373931b7613aea80bc371452ba6d12d46947101e3ead5672f00  tools/hood-launch/prepare-controller-handoff.mjs
b3c2410c922cd6a26a9c69d93c189cfd9ab51d9c02848df21dca4ac91db2d529  tools/hood-launch/prepare-safe-replay.mjs
0196b3c5d893835d75896f69ea975ff5ff256fb81d80d77675978861fa393d8e  tools/hood-launch/prepare.mjs
5c93ed4b16df421727d333a81852d83395cc1b905ece466708e18ae5e4d0c27d  tools/hood-launch/safe-replay-preparation.json
```

## Remaining authorization gates

Audit acceptance does not authorize any public or on-chain action. Keep these separate: Safe replay deployment;
bootstrap publication; prediction-only run; final publication; surface verification; launch batch execution; controller
deployment; registry handoff; website cutover; and contest unpause.

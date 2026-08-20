# VOIDCOIN V4 Rev 2 remediation

Date: August 20, 2026

This addendum responds to `VOIDCOIN_V4_Audit_Rev2.md`. The audit report and its attachments are evidence, not execution
instructions. No deployment, metadata publication, token approval, auction, Safe transaction, or controller unpause
was performed while applying these changes.

## Contract verdict and freeze

The auditor reported no unresolved Critical or High contract finding and found the V4 production contracts suitable
for deployment through `DeployB20V4.s.sol`. The three production Solidity files remain byte-identical to frozen commit
`c7ac786625a92b4c626a5cbfc15816dd2d9a16d1`:

```text
6d92b3f0bc1be43ef93314a9caeb92dfe456a60ae2e3fa6fb08c4d5cd187c361  contracts/src/VOIDB20SkinController.sol
cd18e548b4662690a2dde930b7f8b05e51629d295f260cd7a5e983b3ba82863f  contracts/src/VOIDB20Bootstrapper.sol
2f0d731243ffacfe98553c987d9807c4a3038c3d8e736136e683cc3966e3436c  contracts/script/DeployB20V4.s.sol
```

The auditor's `V4Audit.t.sol` and `V4LiveGate.t.sol` were added as regression evidence; they do not affect production
bytecode.

## Finding closure

| Finding | Resolution |
|---|---|
| H-1 legacy address fallback | Removed. The website fails closed unless both valid V4 B20 addresses are explicitly configured, and API reads verify that the controller governs that token. |
| H-2 burn before moderation | Removed. A private draft has a nullable commitment and moves no tokens. Moderation and IPFS pinning happen first; only the resulting non-null URI-bound commitment becomes executable. The receipt/event is verified before Safe calldata is prepared. |
| Prediction-only surface gate | Predeployment mode now re-derives the token from the live deployer nonce and salt. Postdeployment mode requires explicit token/controller addresses and reads chain ID, token/controller binding, name, symbol, decimals, supply, cap, and contract URI from Base Mainnet. |
| CID length-only check | Replaced by `CID.parse`; both metadata and image response bytes are rehashed as raw and UnixFS content and must match the advertised CID. |
| Metadata/schema gaps | Nonempty description, decimals 18, canonical address fields, `images[]`, `icons[]`, B20 standard fields, full market link object, and six typed market links are required. |
| Blank logo | Rejected using decoded image statistics, in addition to PNG-byte, MIME, square, and minimum-size checks. |
| Unbounded/redirecting gateways | Metadata and image bodies are streamed with size caps; redirects are HTTPS-only, same-origin, and limited to two. |
| Basecat schema evidence | The actual Basecat/PAMPU `contractURI` response, CID, gateway URL, and response SHA-256 are captured in `docs/research/basecat-b20-metadata.json`. Both the rich typed link array and direct link object are published. |
| Stale handoff hashes | This addendum records hashes for the delivery files below; the immutable production-contract hashes remain separately frozen above. |
| Wrong factory text | The handoff now uses canonical `0xB20f000000000000000000000000000000000000`. |

## Verification evidence

- `npm run verify`: ESLint passed; 24 unit tests passed; 39 surface-gate scenarios passed with zero deviations; Next production build passed.
- `forge fmt --check --root contracts`: passed.
- Stock Forge: 163 passed, 0 failed, 9 skipped; auditor `V4Audit` 44/44.
- Base patched Forge full run: 171 passed, 0 failed, 9 skipped; `V4Audit` 44/44, `V4LiveGate` 8/8, `VOIDB20V4` 10/10, with the live-precompile banner.
- Slither: 0 findings across all 11 production targets.
- `npm audit --omit=dev`: 0 production vulnerabilities. Four moderate development-only findings remain in the existing `drizzle-kit`/`esbuild` chain; npm's proposed fix is a breaking dependency change.
- Read-only Base RPC at block `50240310`: chain ID 8453; `base.b20_asset` activated; production Safe has code, three owners, threshold two. No state changed.

The patched-Forge execution uses chain ID 31337 and no Base Mainnet fork. It confirms live-precompile semantics, not
live chain state. The separate RPC checks establish activation and Safe presence/configuration; deployment prediction
must still be rerun immediately before any authorized broadcast.

## Delivery hashes

```text
29be7b5acf3e0e722b322a95adfb6f5920ea36ce57eb162e7b85bf77267c63ad  scripts/publish-b20-genesis.mjs
56de7c6580635a2901302ff165d463296044f81bae3af066bdc2f10ad8239b7e  scripts/verify-b20-genesis.mjs
ad458769d9b7a78a69476d99cc29fdb949bbbaba09bb072725b137ddccf2e58e  scripts/verify-b20-surface-readiness.mjs
71a7820d4f1a6367ab65c6cfd4883df6b495aabcff423ea603e31067aeac361b  scripts/surface-readiness-harness.mjs
dddb24f81a9312f0a0142d31c1548f24394b1c0ce969678086485df9fda2e24b  src/lib/contract.ts
b8c602bd28fbd97f11eebde654a7538729aa61029ac18164169c27cea4ab9cd0  src/lib/token-metadata.ts
6606f3e226ac48e41420a8ee305810dc2057a918c4f6f43ac5ec8cfc71a9c9d3  src/app/api/state/route.ts
cced1a42ebf63fd2c52eb2382ac573ac595bd830e96046860de2a99d089d1c84  src/app/api/requests/route.ts
d276a947e76af01cb867e7cf8908f3be5563c5f2e142fe03fc7a2a0810ed7cb1  src/app/api/admin/requests/[id]/route.ts
6ab4f8adf7e610a26f12ae3d4dd4ed42a222e97f965a07fddcda43bb04ad789b  src/app/api/requests/[id]/confirm/route.ts
a911db7197a87832a93092646ff2031c866c58db27e8a6f6fd075ac9f72a6a2c  src/components/burn-terminal.tsx
d23177b1222466e7dcc3dfb949e8a677751ca3c81383d189211729d88adfd097  src/lib/db/schema.ts
f79d638e1e6d7883a78b1acfbafa18988178a289b6329048d5ec564b538a424b  drizzle/0001_premoderate_before_burn.sql
99acf230e0391f20c8c4537a838eb049602ce4faea93d061bdf3f75141d2fcf9  assets/genesis/metadata.template.json
4677f4cd35184c69b335097a1bd0726ff83f9b445397d9abe31c949c86912cc3  docs/research/basecat-b20-metadata.json
46a2815b8a2e19bb2e9168a3911aa8605c271b2fb918ea3801a3b168a7306bab  package.json
5bfc8b176d074c8432afa52f527f9119492923bf417f681bdaa570066edb4692  package-lock.json
```

## Remaining launch gates

Before public launch: rehearse metadata publication and the full surface verifier on throwaway content; deploy only
under separate authorization; rerun the postdeployment chain-bound verifier; apply the database migration and deploy
the website; create and settle the separately approved Uniswap launch auction; verify Base App/Fomo/Uniswap/DEX
Screener/BaseScan displays; then smoke-test moderation. Unpausing the rename controller remains a separate Safe action.

import sharp from "sharp";
import { CID } from "multiformats/cid";
import * as raw from "multiformats/codecs/raw";
import { sha256 } from "multiformats/hashes/sha2";
import { verifySurfaceReceipt } from "./verify-b20-surface-readiness.mjs";

const WEBSITE = "https://voidcoin.fun";
const TOKEN = "0xB2000000000000000000000000000000000000A1";

async function rawCid(bytes) {
  return CID.createV1(raw.code, await sha256.digest(bytes)).toString();
}

async function png(width, height, alpha = 1) {
  const image = sharp({ create: { width, height, channels: 4, background: { r: 12, g: 35, b: 70, alpha } } });
  if (alpha === 0) return image.png().toBuffer();
  const inset = Math.max(1, Math.floor(Math.min(width, height) / 4));
  return image.composite([{ input: Buffer.from(`<svg width="${width}" height="${height}"><rect x="${inset}" y="${inset}" width="${Math.max(1, width - inset * 2)}" height="${Math.max(1, height - inset * 2)}" fill="#8fffea"/></svg>`) }]).png().toBuffer();
}

function metadata(imageURI) {
  const routes = {
    website: WEBSITE,
    baseApp: `https://base.app/coin/base-mainnet/${TOKEN}`,
    fomo: `https://fomo.family/tokens/base/${TOKEN}`,
    uniswap: `https://app.uniswap.org/explore/tokens/base/${TOKEN}`,
    dexScreener: `https://dexscreener.com/base/${TOKEN}`,
    explorer: `https://basescan.org/token/${TOKEN}`,
  };
  return {
    interop: { erc1046: true, erc7572: true }, name: "VOIDCOIN", symbol: "VOID", standard: "B20",
    token_standard: "B20", launchpad: "VOIDCOIN", launchpadUrl: WEBSITE, decimals: 18,
    description: "VOIDCOIN is a Base-native B20 whose identity follows the highest approved permanent burn record.",
    image: imageURI, images: [imageURI], icons: [imageURI], external_url: WEBSITE, website: WEBSITE,
    chain_id: 8453, contract_address: TOKEN, links: routes,
    market_links: [
      { type: "website", label: "Website", url: routes.website },
      { type: "base", label: "Base App", url: routes.baseApp },
      { type: "fomo", label: "Fomo", url: routes.fomo },
      { type: "uniswap", label: "Uniswap", url: routes.uniswap },
      { type: "dexscreener", label: "DEX Screener", url: routes.dexScreener },
      { type: "explorer", label: "Contract", url: routes.explorer },
    ],
    properties: { network: "Base Mainnet", chainId: 8453, contractAddress: TOKEN, standard: "B20", ...routes },
  };
}

async function fixture({ mutate, imageBytes, servedImageBytes, metadataBytes, servedMetadataBytes } = {}) {
  imageBytes ??= await png(512, 512);
  const imageCid = await rawCid(imageBytes);
  const value = metadata(`ipfs://${imageCid}`);
  mutate?.(value);
  const localMetadataBytes = metadataBytes ?? Buffer.from(JSON.stringify(value));
  const metadataCid = await rawCid(localMetadataBytes);
  const receipt = { imageURI: `ipfs://${imageCid}`, metadataURI: `ipfs://${metadataCid}`, metadata: value, prediction: { token: TOKEN } };
  const publicMetadata = servedMetadataBytes ?? localMetadataBytes;
  const publicImage = servedImageBytes ?? imageBytes;
  const fetchImpl = async (url) => {
    const href = String(url);
    if (href.endsWith(metadataCid)) return new Response(publicMetadata, { status: 200, headers: { "content-type": "application/json", "content-length": String(publicMetadata.length) } });
    return new Response(publicImage, { status: 200, headers: { "content-type": "image/png", "content-length": String(publicImage.length) } });
  };
  return { receipt, expectedAddress: TOKEN, fetchImpl };
}

const scenarios = [{ name: "valid baseline", block: false, make: () => fixture() }];
const mutations = [
  ["name", (m) => { m.name = "WRONG"; }], ["symbol", (m) => { m.symbol = "BAD"; }],
  ["standard", (m) => { m.standard = "ERC20"; }], ["token_standard", (m) => { m.token_standard = "ERC20"; }],
  ["interop", (m) => { m.interop.erc7572 = false; }], ["launchpad", (m) => { m.launchpad = "other"; }],
  ["launchpadUrl", (m) => { m.launchpadUrl = "https://invalid.example"; }], ["decimals", (m) => { m.decimals = 6; }],
  ["description", (m) => { m.description = ""; }], ["website", (m) => { m.website = "https://invalid.example"; }],
  ["external_url", (m) => { m.external_url = "https://invalid.example"; }], ["chain_id", (m) => { m.chain_id = 1; }],
  ["contract_address", (m) => { m.contract_address = "0x" + "de".repeat(20); }],
  ["image", (m) => { m.image = "ipfs://bafkreibogusbogusbogusbogusbogusbogusbogusbogusbogus"; }],
  ["images", (m) => { m.images = []; }], ["icons", (m) => { m.icons = []; }],
  ["links.website", (m) => { m.links.website = "https://invalid.example"; }],
  ["links.baseApp", (m) => { m.links.baseApp = "https://invalid.example"; }],
  ["links.fomo", (m) => { m.links.fomo = "https://invalid.example"; }],
  ["links.uniswap", (m) => { m.links.uniswap = "https://invalid.example"; }],
  ["links.dexScreener", (m) => { m.links.dexScreener = "https://invalid.example"; }],
  ["links.explorer", (m) => { m.links.explorer = "https://invalid.example"; }],
  ["market_links", (m) => { m.market_links.pop(); }], ["properties.network", (m) => { m.properties.network = "Ethereum"; }],
  ["properties.chainId", (m) => { m.properties.chainId = 1; }],
  ["properties.contractAddress", (m) => { m.properties.contractAddress = "0x" + "de".repeat(20); }],
  ["properties.standard", (m) => { m.properties.standard = "ERC20"; }],
  ["properties.baseApp", (m) => { m.properties.baseApp = "https://invalid.example"; }],
  ["properties.fomo", (m) => { m.properties.fomo = "https://invalid.example"; }],
  ["properties.uniswap", (m) => { m.properties.uniswap = "https://invalid.example"; }],
  ["properties.dexScreener", (m) => { m.properties.dexScreener = "https://invalid.example"; }],
  ["properties.explorer", (m) => { m.properties.explorer = "https://invalid.example"; }],
];
for (const [name, mutate] of mutations) scenarios.push({ name: `wrong ${name}`, block: true, make: () => fixture({ mutate }) });

scenarios.push(
  { name: "undersized logo", block: true, make: async () => fixture({ imageBytes: await png(256, 256) }) },
  { name: "non-square logo", block: true, make: async () => fixture({ imageBytes: await png(1024, 512) }) },
  { name: "blank transparent logo", block: true, make: async () => fixture({ imageBytes: await png(512, 512, 0) }) },
  { name: "gateway bytes do not match image CID", block: true, make: async () => fixture({ servedImageBytes: await png(513, 513) }) },
  { name: "gateway bytes do not match metadata CID", block: true, make: async () => fixture({ servedMetadataBytes: Buffer.from(JSON.stringify({ wrong: true })) }) },
  { name: "invalid metadata CID", block: true, make: async () => { const value = await fixture(); value.receipt.metadataURI = `ipfs://${"z".repeat(40)}`; return value; } },
);

let deviations = 0;
for (const scenario of scenarios) {
  let blocked = false;
  let reason = "";
  try { await verifySurfaceReceipt(await scenario.make()); } catch (error) { blocked = true; reason = error instanceof Error ? error.message : String(error); }
  const correct = blocked === scenario.block;
  if (!correct) deviations += 1;
  console.log(`${correct ? "PASS" : "FAIL"} ${scenario.name}: ${blocked ? `blocked (${reason})` : "accepted"}`);
}
console.log(JSON.stringify({ scenarios: scenarios.length, deviations }, null, 2));
if (deviations) process.exitCode = 1;

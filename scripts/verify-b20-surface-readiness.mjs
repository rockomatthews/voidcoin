import { readFile } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const WEBSITE = "https://voidcoin.fun";
const receiptPath = path.resolve(process.argv[2] ?? "assets/genesis/b20-published.json");
const receipt = JSON.parse(await readFile(receiptPath, "utf8"));

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function ipfsCid(uri, label) {
  requireValue(typeof uri === "string" && uri.startsWith("ipfs://"), `${label} must be an ipfs:// URI`);
  const cid = uri.slice(7).replace(/^ipfs\//, "");
  requireValue(cid.length > 20 && !cid.includes("/"), `${label} must contain one IPFS CID`);
  return cid;
}

function assertMetadata(metadata, expectedAddress) {
  requireValue(metadata?.name === "VOIDCOIN", "Genesis metadata name must be VOIDCOIN");
  requireValue(metadata?.symbol === "VOID", "Genesis metadata symbol must be VOID");
  requireValue(metadata?.standard === "B20", "Metadata must expose standard=B20");
  requireValue(metadata?.launchpad === "VOIDCOIN", "Metadata launchpad must truthfully identify VOIDCOIN");
  requireValue(metadata?.launchpadUrl === WEBSITE, "Metadata launchpadUrl must be the official site");
  requireValue(metadata?.website === WEBSITE && metadata?.external_url === WEBSITE, "Metadata must retain the official site");
  requireValue(metadata?.links?.website === WEBSITE, "Metadata must expose links.website in the Basecat-compatible shape");
  requireValue(metadata?.chain_id === 8453, "Metadata chain_id must be Base Mainnet (8453)");
  requireValue(metadata?.contract_address?.toLowerCase() === expectedAddress.toLowerCase(), "Metadata contract address mismatch");
  requireValue(metadata?.properties?.baseApp === `https://base.app/coin/base-mainnet/${expectedAddress}`, "Base App route mismatch");
  requireValue(metadata?.properties?.fomo === `https://fomo.family/tokens/base/${expectedAddress}`, "Fomo route mismatch");
  requireValue(metadata?.properties?.uniswap === `https://app.uniswap.org/explore/tokens/base/${expectedAddress}`, "Uniswap route mismatch");
  requireValue(metadata?.properties?.dexScreener === `https://dexscreener.com/base/${expectedAddress}`, "DexScreener route mismatch");
  requireValue(metadata?.properties?.explorer === `https://basescan.org/token/${expectedAddress}`, "BaseScan route mismatch");
  ipfsCid(metadata?.image, "metadata.image");
}

async function fetchChecked(url, label) {
  const response = await fetch(url, { redirect: "follow", signal: AbortSignal.timeout(20_000) });
  requireValue(response.ok, `${label} returned HTTP ${response.status}`);
  return response;
}

const expectedAddress = receipt?.prediction?.token;
requireValue(/^0x[0-9a-fA-F]{40}$/.test(expectedAddress ?? ""), "Receipt is missing a predicted token address");
assertMetadata(receipt.metadata, expectedAddress);

const metadataCid = ipfsCid(receipt.metadataURI, "receipt.metadataURI");
const imageCid = ipfsCid(receipt.imageURI, "receipt.imageURI");
requireValue(receipt.metadata.image === receipt.imageURI, "Receipt metadata image URI mismatch");

const gateways = [
  "https://gateway.pinata.cloud/ipfs",
  "https://ipfs.io/ipfs",
];

const observations = [];
for (const gateway of gateways) {
  const metadataResponse = await fetchChecked(`${gateway}/${metadataCid}`, `${gateway} metadata`);
  const publicMetadata = await metadataResponse.json();
  assertMetadata(publicMetadata, expectedAddress);
  requireValue(publicMetadata.image === receipt.imageURI, `${gateway} returned a different image URI`);

  const imageResponse = await fetchChecked(`${gateway}/${imageCid}`, `${gateway} image`);
  const contentType = imageResponse.headers.get("content-type")?.split(";")[0];
  requireValue(contentType === "image/png", `${gateway} image must return image/png, got ${contentType ?? "no content type"}`);
  const imageBytes = Buffer.from(await imageResponse.arrayBuffer());
  const image = await sharp(imageBytes).metadata();
  requireValue(image.format === "png", `${gateway} image bytes are not PNG`);
  requireValue(image.width === image.height && (image.width ?? 0) >= 512, `${gateway} logo must be square and at least 512px`);
  observations.push({ gateway, metadataStatus: metadataResponse.status, imageStatus: imageResponse.status, contentType, width: image.width, height: image.height });
}

console.log(JSON.stringify({
  ok: true,
  token: expectedAddress,
  metadataURI: receipt.metadataURI,
  imageURI: receipt.imageURI,
  metadataShape: "Basecat-compatible B20/ERC-7572",
  observations,
}, null, 2));

import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { MemoryBlockstore } from "blockstore-core/memory";
import { importer } from "ipfs-unixfs-importer";
import { CID } from "multiformats/cid";
import * as raw from "multiformats/codecs/raw";
import { sha256 } from "multiformats/hashes/sha2";
import sharp from "sharp";
import { createPublicClient, getAddress, http } from "viem";
import { base } from "viem/chains";
import { b20PredictionFromEnvironment } from "./b20-deployment-addresses.mjs";

const WEBSITE = "https://voidcoin.fun";
const MAX_METADATA_BYTES = 256 * 1024;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const ORIGINAL_SUPPLY = 1_000_000_000n * 10n ** 18n;
const gateways = ["https://gateway.pinata.cloud/ipfs", "https://ipfs.io/ipfs"];

const tokenAbi = [
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "supplyCap", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "contractURI", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
];
const controllerAbi = [{ type: "function", name: "token", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] }];

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

export function ipfsCid(uri, label) {
  requireValue(typeof uri === "string" && /^ipfs:\/\/[^/]+$/.test(uri), `${label} must contain exactly one IPFS CID`);
  try {
    return CID.parse(uri.slice(7));
  } catch {
    throw new Error(`${label} is not a valid CID`);
  }
}

function expectedRoutes(address) {
  return {
    website: WEBSITE,
    baseApp: `https://base.app/coin/base-mainnet/${address}`,
    fomo: `https://fomo.family/tokens/base/${address}`,
    uniswap: `https://app.uniswap.org/explore/tokens/base/${address}`,
    dexScreener: `https://dexscreener.com/base/${address}`,
    explorer: `https://basescan.org/token/${address}`,
  };
}

export function assertMetadata(metadata, expectedAddress, expectedImageURI) {
  const routes = expectedRoutes(expectedAddress);
  const typedRoutes = [
    { type: "website", label: "Website", url: routes.website },
    { type: "base", label: "Base App", url: routes.baseApp },
    { type: "fomo", label: "Fomo", url: routes.fomo },
    { type: "uniswap", label: "Uniswap", url: routes.uniswap },
    { type: "dexscreener", label: "DEX Screener", url: routes.dexScreener },
    { type: "explorer", label: "Contract", url: routes.explorer },
  ];
  requireValue(metadata?.name === "VOIDCOIN", "Genesis metadata name must be VOIDCOIN");
  requireValue(metadata?.symbol === "VOID", "Genesis metadata symbol must be VOID");
  requireValue(metadata?.standard === "B20" && metadata?.token_standard === "B20", "Metadata standard must be B20");
  requireValue(metadata?.interop?.erc1046 === true && metadata?.interop?.erc7572 === true, "Metadata interop flags are incomplete");
  requireValue(metadata?.launchpad === "VOIDCOIN" && metadata?.launchpadUrl === WEBSITE, "Metadata launch source is wrong");
  requireValue(metadata?.decimals === 18, "Metadata decimals must be 18");
  requireValue(typeof metadata?.description === "string" && metadata.description.trim().length >= 40, "Metadata description is missing or too short");
  requireValue(metadata?.website === WEBSITE && metadata?.external_url === WEBSITE, "Metadata must retain the official site");
  requireValue(metadata?.chain_id === 8453, "Metadata chain_id must be Base Mainnet (8453)");
  requireValue(metadata?.contract_address?.toLowerCase() === expectedAddress.toLowerCase(), "Metadata contract address mismatch");
  requireValue(metadata?.image === expectedImageURI, "Metadata image URI mismatch");
  requireValue(JSON.stringify(metadata?.images) === JSON.stringify([expectedImageURI]), "Metadata images[] must match image");
  requireValue(JSON.stringify(metadata?.icons) === JSON.stringify([expectedImageURI]), "Metadata icons[] must match image");
  requireValue(JSON.stringify(metadata?.links) === JSON.stringify(routes), "Metadata links object is incomplete or wrong");
  requireValue(JSON.stringify(metadata?.market_links) === JSON.stringify(typedRoutes), "Metadata typed market links are incomplete or wrong");
  requireValue(metadata?.properties?.network === "Base Mainnet" && metadata?.properties?.chainId === 8453, "Metadata network properties mismatch");
  requireValue(metadata?.properties?.contractAddress?.toLowerCase() === expectedAddress.toLowerCase(), "Metadata properties.contractAddress mismatch");
  requireValue(metadata?.properties?.standard === "B20", "Metadata properties.standard must be B20");
  for (const [key, value] of Object.entries(routes)) requireValue(metadata?.properties?.[key] === value, `Metadata properties.${key} mismatch`);
  ipfsCid(metadata.image, "metadata.image");
}

async function fetchBytesChecked(initialUrl, label, maximumBytes, fetchImpl = fetch) {
  let current = new URL(initialUrl);
  const originalOrigin = current.origin;
  for (let redirects = 0; redirects <= 2; redirects += 1) {
    const accept = label.endsWith(" metadata") ? "application/json" : "image/png";
    const response = await fetchImpl(current, { redirect: "manual", headers: { Accept: accept }, signal: AbortSignal.timeout(45_000) });
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get("location");
      requireValue(location, `${label} returned a redirect without Location`);
      const next = new URL(location, current);
      requireValue(next.protocol === "https:" && next.origin === originalOrigin, `${label} redirected outside its HTTPS gateway origin`);
      current = next;
      continue;
    }
    requireValue(response.ok, `${label} returned HTTP ${response.status}`);
    const declaredLength = Number(response.headers.get("content-length") ?? "0");
    requireValue(!declaredLength || declaredLength <= maximumBytes, `${label} exceeds the ${maximumBytes}-byte limit`);
    requireValue(response.body, `${label} returned no body`);
    const chunks = [];
    let length = 0;
    for await (const chunk of response.body) {
      const bytes = Buffer.from(chunk);
      length += bytes.length;
      requireValue(length <= maximumBytes, `${label} exceeds the ${maximumBytes}-byte limit`);
      chunks.push(bytes);
    }
    return { bytes: Buffer.concat(chunks), contentType: response.headers.get("content-type")?.split(";")[0] ?? null, status: response.status };
  }
  throw new Error(`${label} exceeded the two-redirect limit`);
}

async function cidCandidates(bytes, target) {
  const digest = await sha256.digest(bytes);
  const candidates = [CID.createV1(raw.code, digest)];
  for (const rawLeaves of [true, false]) {
    if (target.version === 0 && rawLeaves) continue;
    const blockstore = new MemoryBlockstore();
    for await (const entry of importer([{ content: bytes }], blockstore, { cidVersion: target.version, rawLeaves })) candidates.push(entry.cid);
  }
  return candidates;
}

export async function assertBytesMatchCid(bytes, cid, label) {
  const candidates = await cidCandidates(bytes, cid);
  requireValue(candidates.some((candidate) => candidate.equals(cid)), `${label} bytes do not hash to ${cid}`);
}

async function assertLogo(imageBytes, gateway) {
  const image = await sharp(imageBytes).metadata();
  requireValue(image.format === "png", `${gateway} image bytes are not PNG`);
  requireValue(image.width === image.height && (image.width ?? 0) >= 512, `${gateway} logo must be square and at least 512px`);
  const stats = await sharp(imageBytes).ensureAlpha().stats();
  requireValue((stats.channels[3]?.max ?? 0) > 0 && stats.entropy > 0.05, `${gateway} logo is blank or fully transparent`);
  return image;
}

export async function verifySurfaceReceipt({ receipt, expectedAddress, fetchImpl = fetch }) {
  assertMetadata(receipt.metadata, expectedAddress, receipt.imageURI);
  const metadataCid = ipfsCid(receipt.metadataURI, "receipt.metadataURI");
  const imageCid = ipfsCid(receipt.imageURI, "receipt.imageURI");
  requireValue(receipt.metadata.image === receipt.imageURI, "Receipt metadata image URI mismatch");
  const observations = [];
  for (const gateway of gateways) {
    const metadataResponse = await fetchBytesChecked(`${gateway}/${metadataCid}`, `${gateway} metadata`, MAX_METADATA_BYTES, fetchImpl);
    requireValue(metadataResponse.contentType === "application/json", `${gateway} metadata must return application/json`);
    await assertBytesMatchCid(metadataResponse.bytes, metadataCid, `${gateway} metadata`);
    let publicMetadata;
    try { publicMetadata = JSON.parse(metadataResponse.bytes.toString("utf8")); } catch { throw new Error(`${gateway} metadata is not valid JSON`); }
    requireValue(isDeepStrictEqual(publicMetadata, receipt.metadata), `${gateway} metadata differs from receipt.metadata`);
    assertMetadata(publicMetadata, expectedAddress, receipt.imageURI);
    const imageResponse = await fetchBytesChecked(`${gateway}/${imageCid}`, `${gateway} image`, MAX_IMAGE_BYTES, fetchImpl);
    requireValue(imageResponse.contentType === "image/png", `${gateway} image must return image/png, got ${imageResponse.contentType ?? "no content type"}`);
    await assertBytesMatchCid(imageResponse.bytes, imageCid, `${gateway} image`);
    const image = await assertLogo(imageResponse.bytes, gateway);
    observations.push({ gateway, metadataStatus: metadataResponse.status, imageStatus: imageResponse.status, contentType: imageResponse.contentType, width: image.width, height: image.height });
  }
  return observations;
}

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? null : process.argv[index + 1] ?? null;
}

async function expectedAddressForPhase(receipt) {
  const deployedToken = argument("--token");
  if (!deployedToken) {
    const prediction = await b20PredictionFromEnvironment();
    requireValue(receipt?.prediction?.token?.toLowerCase() === prediction.token.toLowerCase(), "Receipt token prediction is stale");
    requireValue(receipt?.prediction?.deployerNonce === prediction.deployerNonce, "Receipt deployer nonce is stale");
    requireValue(receipt?.prediction?.salt?.toLowerCase() === prediction.salt.toLowerCase(), "Receipt salt is stale");
    return { address: prediction.token, phase: "predeploy-prediction" };
  }
  const address = getAddress(deployedToken);
  const controllerValue = argument("--controller");
  requireValue(controllerValue, "--controller is required with --token");
  const controller = getAddress(controllerValue);
  const rpcUrl = process.env.BASE_MAINNET_RPC_URL?.trim();
  requireValue(rpcUrl, "BASE_MAINNET_RPC_URL is required for deployed verification");
  requireValue(receipt?.prediction?.token?.toLowerCase() === address.toLowerCase(), "Deployed token differs from the published receipt");
  requireValue(receipt?.prediction?.controller?.toLowerCase() === controller.toLowerCase(), "Deployed controller differs from the published receipt");
  const client = createPublicClient({ chain: base, transport: http(rpcUrl) });
  requireValue(await client.getChainId() === base.id, "RPC is not Base Mainnet");
  const [name, symbol, decimals, totalSupply, supplyCap, contractURI, controllerToken] = await Promise.all([
    client.readContract({ address, abi: tokenAbi, functionName: "name" }),
    client.readContract({ address, abi: tokenAbi, functionName: "symbol" }),
    client.readContract({ address, abi: tokenAbi, functionName: "decimals" }),
    client.readContract({ address, abi: tokenAbi, functionName: "totalSupply" }),
    client.readContract({ address, abi: tokenAbi, functionName: "supplyCap" }),
    client.readContract({ address, abi: tokenAbi, functionName: "contractURI" }),
    client.readContract({ address: controller, abi: controllerAbi, functionName: "token" }),
  ]);
  requireValue(name === "VOIDCOIN" && symbol === "VOID" && decimals === 18, "Deployed token identity differs from genesis");
  requireValue(totalSupply === ORIGINAL_SUPPLY && supplyCap === ORIGINAL_SUPPLY, "Deployed token supply or cap differs from one billion");
  requireValue(contractURI === receipt.metadataURI, "Deployed contractURI differs from the published receipt");
  requireValue(controllerToken.toLowerCase() === address.toLowerCase(), "Controller does not point to the deployed token");
  return { address, controller, phase: "deployed-base-mainnet" };
}

export async function main() {
  const consumed = new Set([process.argv.indexOf("--token") + 1, process.argv.indexOf("--controller") + 1]);
  const positional = process.argv.slice(2).find((value, index) => !value.startsWith("--") && !consumed.has(index + 2));
  const receiptPath = path.resolve(positional ?? "assets/genesis/b20-published.json");
  const receipt = JSON.parse(await readFile(receiptPath, "utf8"));
  const expected = await expectedAddressForPhase(receipt);
  const observations = await verifySurfaceReceipt({ receipt, expectedAddress: expected.address });
  console.log(JSON.stringify({ ok: true, phase: expected.phase, token: expected.address, controller: expected.controller ?? null, metadataURI: receipt.metadataURI, imageURI: receipt.imageURI, metadataShape: "B20/ERC-7572 plus typed market routes", observations }, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();

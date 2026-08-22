import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  createPublicClient,
  encodeFunctionData,
  getAddress,
  http,
  isAddress,
  keccak256,
  parseAbi,
  stringToHex,
} from "viem";
import { defineChain } from "viem";

const CHAIN_ID = 4663;
const RPC_URL = process.env.ROBINHOOD_MAINNET_RPC_URL?.trim() || "https://rpc.mainnet.chain.robinhood.com";
const SAFE = "0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9";
const LAUNCHER = "0x5e4121c262B846eb518EF3EADCD5566838AA841F";
const OWNER_REGISTRY = "0xEBbf66e306cE0Df652898A4894f6aBAF09F8Cd58";
const EXPECTED_LAUNCHER_CODE_HASH = "0xbe8f598c66a8a559faef2a6aea9b79273de6b439ba2d47e3b6af35c8364042c9";
const EXPECTED_REGISTRY_CODE_HASH = "0xd106a4c613f6c254c316010ff7169ab308f6a669ed5a5d9a42bc449c8866b265";
const VENUE_ID = 1;
const DEFAULT_SUPPLY = 1_000_000_000n * 10n ** 18n;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const robinhood = defineChain({
  id: CHAIN_ID,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: "Blockscout", url: "https://robinhoodchain.blockscout.com" } },
});

const launcherAbi = parseAbi([
  "function launchFee() view returns (uint256)",
  "function minFdvWei() view returns (uint256)",
  "function maxFdvWei() view returns (uint256)",
  "function minSupply() view returns (uint256)",
  "function maxSupply() view returns (uint256)",
  "function venueExists(uint8 venueId) view returns (bool)",
  "function computeTokenAddress(address deployer,(uint8 venueId,string name,string symbol,string image,string description,string socials,string metadataURI,bytes32 userSalt,int24 tickIfToken0IsNewToken,uint256 supply,bool sniperGuard,uint256 devBuyMinOut,bytes tokenFeeConfig,bytes creatorFeeConfig) p) view returns(address)",
  "function launch((uint8 venueId,string name,string symbol,string image,string description,string socials,string metadataURI,bytes32 userSalt,int24 tickIfToken0IsNewToken,uint256 supply,bool sniperGuard,uint256 devBuyMinOut,bytes tokenFeeConfig,bytes creatorFeeConfig) p) payable returns(address token,address pool,uint256 positionId)",
]);

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

async function optionalJson(file) {
  try { return JSON.parse(await readFile(resolve(file), "utf8")); } catch { return null; }
}

function assertUri(name, value) {
  if (!/^ipfs:\/\/[A-Za-z0-9]+$/.test(value)) throw new Error(`${name} must contain exactly one IPFS CID`);
  if (value.length > 512) throw new Error(`${name} is too long`);
}

function json(value) {
  return `${JSON.stringify(value, (_, item) => typeof item === "bigint" ? item.toString() : item, 2)}\n`;
}

const bootstrapReceipt = await optionalJson("assets/genesis/hood-bootstrap-published.json");
const finalReceipt = await optionalJson("assets/genesis/hood-published.json");
const image = process.env.VOID_HOOD_IMAGE_URI?.trim() || bootstrapReceipt?.imageURI;
const metadataURI = process.env.VOID_HOOD_METADATA_URI?.trim() || bootstrapReceipt?.metadataURI;
const description = process.env.VOID_HOOD_DESCRIPTION?.trim() || bootstrapReceipt?.metadata?.description;
const socials = process.env.VOID_HOOD_SOCIALS?.trim() || JSON.stringify({ website: "https://voidcoin.fun" });
if (!image || !metadataURI || !description) throw new Error("Publish Hood bootstrap metadata first or provide all VOID_HOOD_* metadata values");
const finalMetadataURI = process.env.VOID_HOOD_FINAL_METADATA_URI?.trim() || finalReceipt?.metadataURI || null;
const startTickText = required("VOID_HOOD_START_TICK");
if (!/^-?\d+$/.test(startTickText)) throw new Error("VOID_HOOD_START_TICK must be an integer");
const startTick = Number(startTickText);
if (!Number.isSafeInteger(startTick) || startTick % 200 !== 0 || startTick < -887200 || startTick > 887200) {
  throw new Error("VOID_HOOD_START_TICK must be a valid multiple of 200");
}
assertUri("VOID_HOOD_IMAGE_URI", image);
assertUri("VOID_HOOD_METADATA_URI", metadataURI);
if (finalMetadataURI) assertUri("VOID_HOOD_FINAL_METADATA_URI", finalMetadataURI);
if (description.length === 0 || description.length > 2_048) throw new Error("VOID_HOOD_DESCRIPTION length is invalid");
const parsedSocials = JSON.parse(socials);
if (!parsedSocials || Array.isArray(parsedSocials) || typeof parsedSocials !== "object") throw new Error("VOID_HOOD_SOCIALS must be a JSON object");
for (const [key, value] of Object.entries(parsedSocials)) {
  if (!/^[A-Za-z0-9_-]+$/.test(key) || typeof value !== "string" || !value.startsWith("https://")) {
    throw new Error("VOID_HOOD_SOCIALS accepts only compact HTTPS string links");
  }
}

const userSalt = process.env.VOID_HOOD_USER_SALT?.trim() || keccak256(stringToHex(`VOIDCOIN-V5-${metadataURI}`));
if (!/^0x[0-9a-fA-F]{64}$/.test(userSalt)) throw new Error("VOID_HOOD_USER_SALT must be bytes32");

const client = createPublicClient({ chain: robinhood, transport: http(RPC_URL) });
const chainId = await client.getChainId();
if (chainId !== CHAIN_ID) throw new Error(`RPC chain ${chainId}; expected ${CHAIN_ID}`);
const [blockNumber, launcherCode, safeCode, registryCode, launchFee, minFdvWei, maxFdvWei, minSupply, maxSupply, venueExists] =
  await Promise.all([
    client.getBlockNumber(),
    client.getBytecode({ address: LAUNCHER }),
    client.getBytecode({ address: SAFE }),
    client.getBytecode({ address: OWNER_REGISTRY }),
    client.readContract({ address: LAUNCHER, abi: launcherAbi, functionName: "launchFee" }),
    client.readContract({ address: LAUNCHER, abi: launcherAbi, functionName: "minFdvWei" }),
    client.readContract({ address: LAUNCHER, abi: launcherAbi, functionName: "maxFdvWei" }),
    client.readContract({ address: LAUNCHER, abi: launcherAbi, functionName: "minSupply" }),
    client.readContract({ address: LAUNCHER, abi: launcherAbi, functionName: "maxSupply" }),
    client.readContract({ address: LAUNCHER, abi: launcherAbi, functionName: "venueExists", args: [VENUE_ID] }),
  ]);

if (!launcherCode || !safeCode || !registryCode) throw new Error("launcher, Safe, or registry has no code");
if (keccak256(launcherCode) !== EXPECTED_LAUNCHER_CODE_HASH) throw new Error("live HoodLauncher bytecode does not match the reviewed deployment");
if (keccak256(registryCode) !== EXPECTED_REGISTRY_CODE_HASH) throw new Error("live TokenOwnerRegistry bytecode does not match the reviewed deployment");
if (!venueExists) throw new Error("Uniswap V3 launch venue is not registered");
if (DEFAULT_SUPPLY < minSupply || DEFAULT_SUPPLY > maxSupply) {
  throw new Error("one-billion supply is outside the live launcher bounds");
}

// HoodLauncher defines this field as the normalized tick when the new token is
// token0 and inverts it internally when CREATE2 ordering makes the token token1.
const normalizedApproximateFdvWei = Math.exp(Math.log(1.0001) * startTick) * 1_000_000_000 * 1e18;
if (!Number.isFinite(normalizedApproximateFdvWei) || normalizedApproximateFdvWei < Number(minFdvWei) * 1.01 || normalizedApproximateFdvWei > Number(maxFdvWei) * 0.99) {
  throw new Error("starting tick is not safely inside the live FDV bounds");
}

const params = {
  venueId: VENUE_ID,
  name: "VOIDCOIN",
  symbol: "VOID",
  image,
  description,
  socials,
  metadataURI,
  userSalt,
  tickIfToken0IsNewToken: startTick,
  supply: DEFAULT_SUPPLY,
  sniperGuard: true,
  devBuyMinOut: 0n,
  tokenFeeConfig: "0x",
  creatorFeeConfig: "0x",
};

const predictedToken = getAddress(await client.readContract({
  address: LAUNCHER,
  abi: launcherAbi,
  functionName: "computeTokenAddress",
  args: [SAFE, params],
}));
if (!isAddress(predictedToken) || predictedToken === ZERO_ADDRESS) throw new Error("invalid predicted token");
if (await client.getBytecode({ address: predictedToken })) throw new Error("predicted token address is already deployed");
if (finalReceipt) {
  if (finalReceipt.prediction?.token?.toLowerCase() !== predictedToken.toLowerCase()) throw new Error("Final metadata was pinned for a different predicted token");
  if (finalReceipt.prediction?.bootstrapMetadataURI !== metadataURI) throw new Error("Final metadata was pinned from a different bootstrap document");
}
const predictionOnly = process.env.VOID_HOOD_PREDICTION_ONLY === "true";
if (!finalMetadataURI && !predictionOnly) throw new Error("Final address-bound metadata is required; use VOID_HOOD_PREDICTION_ONLY=true only for the first prediction pass");

const data = encodeFunctionData({ abi: launcherAbi, functionName: "launch", args: [params] });
const finalMetadataData = finalMetadataURI ? encodeFunctionData({
  abi: parseAbi(["function setContractURI(string nextContractURI)"]),
  functionName: "setContractURI",
  args: [finalMetadataURI],
}) : null;
const createdAt = Date.now();
const outputDir = resolve("tools/hood-launch");
await mkdir(outputDir, { recursive: true });

const receipt = {
  status: finalMetadataURI ? "PREPARED_NOT_EXECUTED" : "PREDICTION_ONLY_FINAL_METADATA_REQUIRED",
  warning: "Review only. Nothing has been signed, broadcast, or launched.",
  createdAt,
  chain: { chainId, blockNumber, rpc: RPC_URL },
  deployment: { safe: SAFE, launcher: LAUNCHER, ownerRegistry: OWNER_REGISTRY, predictedToken },
  launch: { ...params, bootstrapMetadataURI: metadataURI, finalMetadataURI, launchFee, minFdvWei, maxFdvWei, normalizedApproximateFdvWei: Math.floor(normalizedApproximateFdvWei).toString() },
  buying: {
    fomo: `https://fomo.family/tokens/robinhood/${predictedToken}`,
    hoodTerminal: "https://hood.dev",
    hoodInstructions: `Paste ${predictedToken} into hood.dev search`,
    explorer: `https://robinhoodchain.blockscout.com/token/${predictedToken}`,
  },
  guarantees: {
    tradeableAtConfirmation: true,
    graduationRequired: false,
    migrationRequired: false,
    nominalLaunchSupply: "1000000000",
    supplyDustBehavior: "HoodLauncher burns the few token wei that Uniswap V3 liquidity rounding cannot place",
    maximumAcceptedLaunchDustWei: "1000000",
    mintingAfterLaunch: false,
    immutableErc20NameAndSymbol: true,
    controllerHandoffIncluded: false,
    finalAddressBoundMetadataAppliedInLaunchBatch: Boolean(finalMetadataURI),
  },
};

const safeFile = {
  version: "1.0",
  chainId: String(CHAIN_ID),
  createdAt,
  meta: {
    name: "Launch VOIDCOIN V5 on Robinhood Chain",
    description: `Immediate Uniswap V3 launch for predicted token ${predictedToken}`,
    txBuilderVersion: "1.18.0",
    createdFromSafeAddress: SAFE,
    createdFromOwnerAddress: "",
    checksum: "",
  },
  transactions: finalMetadataData ? [
    { to: LAUNCHER, value: launchFee.toString(), data, contractMethod: null, contractInputsValues: null },
    { to: predictedToken, value: "0", data: finalMetadataData, contractMethod: null, contractInputsValues: null },
  ] : [],
};

await Promise.all([
  writeFile(resolve(outputDir, "launch-preparation.json"), json(receipt)),
  writeFile(resolve(outputDir, "safe-launch.json"), json(safeFile)),
]);

console.log(json({ status: receipt.status, predictedToken, launchFeeWei: launchFee, blockNumber }));

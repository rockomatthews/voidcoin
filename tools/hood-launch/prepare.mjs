import { mkdir, writeFile } from "node:fs/promises";
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

function assertUri(name, value) {
  if (!value.startsWith("ipfs://") && !value.startsWith("ar://") && !value.startsWith("https://")) {
    throw new Error(`${name} must use ipfs://, ar://, or https://`);
  }
  if (value.length > 512) throw new Error(`${name} is too long`);
}

function json(value) {
  return `${JSON.stringify(value, (_, item) => typeof item === "bigint" ? item.toString() : item, 2)}\n`;
}

const image = required("VOID_HOOD_IMAGE_URI");
const metadataURI = required("VOID_HOOD_METADATA_URI");
const description = required("VOID_HOOD_DESCRIPTION");
const socials = required("VOID_HOOD_SOCIALS");
const startTickText = required("VOID_HOOD_START_TICK");
if (!/^-?\d+$/.test(startTickText)) throw new Error("VOID_HOOD_START_TICK must be an integer");
const startTick = Number(startTickText);
if (!Number.isSafeInteger(startTick) || startTick % 200 !== 0 || startTick < -887200 || startTick > 887200) {
  throw new Error("VOID_HOOD_START_TICK must be a valid multiple of 200");
}
assertUri("VOID_HOOD_IMAGE_URI", image);
assertUri("VOID_HOOD_METADATA_URI", metadataURI);
if (description.length === 0 || description.length > 2_048) throw new Error("VOID_HOOD_DESCRIPTION length is invalid");
JSON.parse(socials);

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
if (!venueExists) throw new Error("Uniswap V3 launch venue is not registered");
if (DEFAULT_SUPPLY < minSupply * 10n ** 18n || DEFAULT_SUPPLY > maxSupply * 10n ** 18n) {
  throw new Error("one-billion supply is outside the live launcher bounds");
}

const approximateFdvWei = Math.exp(Math.log(1.0001) * startTick) * 1_000_000_000 * 1e18;
if (!Number.isFinite(approximateFdvWei) || approximateFdvWei < Number(minFdvWei) * 1.01 || approximateFdvWei > Number(maxFdvWei) * 0.99) {
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

const data = encodeFunctionData({ abi: launcherAbi, functionName: "launch", args: [params] });
const createdAt = Date.now();
const outputDir = resolve("tools/hood-launch");
await mkdir(outputDir, { recursive: true });

const receipt = {
  status: "PREPARED_NOT_EXECUTED",
  warning: "Review only. Nothing has been signed, broadcast, or launched.",
  createdAt,
  chain: { chainId, blockNumber, rpc: RPC_URL },
  deployment: { safe: SAFE, launcher: LAUNCHER, ownerRegistry: OWNER_REGISTRY, predictedToken },
  launch: { ...params, launchFee, minFdvWei, maxFdvWei, approximateFdvWei: Math.floor(approximateFdvWei).toString() },
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
  transactions: [{ to: LAUNCHER, value: launchFee.toString(), data, contractMethod: null, contractInputsValues: null }],
};

await Promise.all([
  writeFile(resolve(outputDir, "launch-preparation.json"), json(receipt)),
  writeFile(resolve(outputDir, "safe-launch.json"), json(safeFile)),
]);

console.log(json({ status: receipt.status, predictedToken, launchFeeWei: launchFee, blockNumber }));

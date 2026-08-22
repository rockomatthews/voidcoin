import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createPublicClient, encodeFunctionData, getAddress, http, isAddress, parseAbi } from "viem";
import { defineChain } from "viem";

const CHAIN_ID = 4663;
const NOMINAL_SUPPLY = 1_000_000_000n * 10n ** 18n;
const MAX_LAUNCH_DUST = 1_000_000n;
const RPC_URL = process.env.ROBINHOOD_MAINNET_RPC_URL?.trim() || "https://rpc.mainnet.chain.robinhood.com";
const SAFE = "0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9";
const REGISTRY = "0xEBbf66e306cE0Df652898A4894f6aBAF09F8Cd58";
const token = getAddress(process.env.VOID_HOOD_TOKEN?.trim() || "");
const controller = getAddress(process.env.VOID_HOOD_CONTROLLER?.trim() || "");
if (!isAddress(token) || !isAddress(controller)) throw new Error("VOID_HOOD_TOKEN and VOID_HOOD_CONTROLLER are required");

const chain = defineChain({
  id: CHAIN_ID,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
});
const registryAbi = parseAbi([
  "function ownerOf(address token) view returns(address)",
  "function transferTokenOwnership(address token,address newOwner)",
]);
const tokenAbi = parseAbi([
  "function name() view returns(string)",
  "function symbol() view returns(string)",
  "function totalSupply() view returns(uint256)",
  "function tokenOwner() view returns(address)",
]);
const controllerAbi = parseAbi([
  "function owner() view returns(address)",
  "function token() view returns(address)",
  "function ownerRegistry() view returns(address)",
  "function renamePaused() view returns(bool)",
  "function controllerReady() view returns(bool)",
  "function launchSupply() view returns(uint256)",
]);
const client = createPublicClient({ chain, transport: http(RPC_URL) });
const [chainId, registryOwner, tokenOwner, name, symbol, supply, controllerOwner, governedToken, governedRegistry, paused, ready, launchSupply] =
  await Promise.all([
    client.getChainId(),
    client.readContract({ address: REGISTRY, abi: registryAbi, functionName: "ownerOf", args: [token] }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "tokenOwner" }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "name" }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "symbol" }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "totalSupply" }),
    client.readContract({ address: controller, abi: controllerAbi, functionName: "owner" }),
    client.readContract({ address: controller, abi: controllerAbi, functionName: "token" }),
    client.readContract({ address: controller, abi: controllerAbi, functionName: "ownerRegistry" }),
    client.readContract({ address: controller, abi: controllerAbi, functionName: "renamePaused" }),
    client.readContract({ address: controller, abi: controllerAbi, functionName: "controllerReady" }),
    client.readContract({ address: controller, abi: controllerAbi, functionName: "launchSupply" }),
  ]);

const same = (a, b) => a.toLowerCase() === b.toLowerCase();
if (chainId !== CHAIN_ID || !same(registryOwner, SAFE) || !same(tokenOwner, SAFE)) throw new Error("Safe is not current token owner");
if (name !== "VOIDCOIN" || symbol !== "VOID") throw new Error("token identity mismatch");
if (supply > NOMINAL_SUPPLY || supply + MAX_LAUNCH_DUST < NOMINAL_SUPPLY) throw new Error("token launch supply mismatch");
if (!same(controllerOwner, SAFE) || !same(governedToken, token) || !same(governedRegistry, REGISTRY)) throw new Error("controller freeze mismatch");
if (launchSupply !== supply) throw new Error("controller launch-supply baseline mismatch");
if (!paused || ready) throw new Error("controller must be paused and not ready before handoff");

const data = encodeFunctionData({
  abi: registryAbi,
  functionName: "transferTokenOwnership",
  args: [token, controller],
});
const createdAt = Date.now();
const safeFile = {
  version: "1.0",
  chainId: String(CHAIN_ID),
  createdAt,
  meta: {
    name: "Hand VOIDCOIN V5 metadata control to controller",
    description: `Transfer Hood token ownership for ${token} to paused controller ${controller}`,
    txBuilderVersion: "1.18.0",
    createdFromSafeAddress: SAFE,
    createdFromOwnerAddress: "",
    checksum: "",
  },
  transactions: [{ to: REGISTRY, value: "0", data, contractMethod: null, contractInputsValues: null }],
};

const outputDir = resolve("tools/hood-launch");
await mkdir(outputDir, { recursive: true });
await writeFile(resolve(outputDir, "safe-controller-handoff.json"), `${JSON.stringify(safeFile, null, 2)}\n`);
console.log(JSON.stringify({ status: "PREPARED_NOT_EXECUTED", token, controller, registry: REGISTRY }, null, 2));

import { readFile } from "node:fs/promises";
import path from "node:path";
import { createPublicClient, defineChain, getAddress, http, toFunctionSelector } from "viem";
import { verifySurfaceReceipt } from "./verify-b20-surface-readiness.mjs";

const WEBSITE = "https://voidcoin.fun";
const ORIGINAL_SUPPLY = 1_000_000_000n * 10n ** 18n;
const MAX_LAUNCH_DUST = 1_000_000n;

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function routes(address) {
  return {
    website: WEBSITE,
    fomo: `https://fomo.family/tokens/robinhood/${address}`,
    hoodTerminal: "https://hood.dev",
    walletHelp: "https://robinhood.com/us/en/support/articles/robinhood-wallet/",
    dexScreener: `https://dexscreener.com/robinhood/${address}`,
    explorer: `https://robinhoodchain.blockscout.com/token/${address}`,
  };
}

export function assertHoodMetadata(metadata, expectedAddress, expectedImageURI) {
  const expectedRoutes = routes(expectedAddress);
  const marketLinks = [
    { type: "website", label: "Website", url: expectedRoutes.website },
    { type: "fomo", label: "Buy on Fomo", url: expectedRoutes.fomo },
    { type: "terminal", label: "hood.dev", url: expectedRoutes.hoodTerminal },
    { type: "dexscreener", label: "DEX Screener", url: expectedRoutes.dexScreener },
    { type: "explorer", label: "Contract", url: expectedRoutes.explorer },
    { type: "wallet-help", label: "Robinhood Wallet help", url: expectedRoutes.walletHelp },
  ];
  requireValue(metadata?.name === "VOIDCOIN" && metadata?.symbol === "VOID", "Genesis token identity must be VOIDCOIN (VOID)");
  requireValue(metadata?.decimals === 18, "Metadata decimals must be 18");
  requireValue(typeof metadata?.description === "string" && metadata.description.trim().length >= 80, "Metadata description is missing or too short");
  requireValue(metadata?.image === expectedImageURI, "Metadata image URI mismatch");
  requireValue(metadata?.website === WEBSITE && metadata?.external_url === WEBSITE, "Official website metadata mismatch");
  requireValue(metadata?.chain_id === 4663, "Metadata chain_id must be Robinhood Chain (4663)");
  requireValue(metadata?.contract_address?.toLowerCase() === expectedAddress.toLowerCase(), "Metadata contract address mismatch");
  requireValue(JSON.stringify(metadata?.links) === JSON.stringify(expectedRoutes), "Metadata links object is incomplete or wrong");
  requireValue(JSON.stringify(metadata?.market_links) === JSON.stringify(marketLinks), "Metadata typed market links are incomplete or wrong");
  requireValue(metadata?.properties?.network === "Robinhood Chain" && metadata?.properties?.chainId === 4663, "Metadata network properties mismatch");
  requireValue(metadata?.properties?.contractAddress?.toLowerCase() === expectedAddress.toLowerCase(), "Metadata properties.contractAddress mismatch");
  requireValue(metadata?.properties?.launchpad === "hood.dev", "Metadata launchpad mismatch");
  requireValue(metadata?.properties?.immutableErc20Name === "VOIDCOIN" && metadata?.properties?.immutableErc20Symbol === "VOID", "Immutable wallet identity disclosure is missing");
  requireValue(metadata?.properties?.displayName === "VOIDCOIN" && metadata?.properties?.displaySymbol === "VOID", "Genesis display identity mismatch");
}

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? null : process.argv[index + 1] ?? null;
}

const receiptPath = path.resolve(argument("--receipt") ?? "assets/genesis/hood-published.json");
const preparationPath = path.resolve(argument("--preparation") ?? "tools/hood-launch/launch-preparation.json");
const [receipt, preparation, safeBatch] = await Promise.all([
  readFile(receiptPath, "utf8").then(JSON.parse),
  readFile(preparationPath, "utf8").then(JSON.parse),
  readFile(path.resolve("tools/hood-launch/safe-launch.json"), "utf8").then(JSON.parse),
]);
const predictedToken = getAddress(preparation?.deployment?.predictedToken);
requireValue(receipt?.prediction?.token?.toLowerCase() === predictedToken.toLowerCase(), "Final metadata receipt does not match the live launch prediction");
requireValue(receipt?.prediction?.bootstrapMetadataURI === preparation?.launch?.metadataURI, "Bootstrap metadata mismatch");
requireValue(preparation?.launch?.finalMetadataURI === receipt.metadataURI, "Launch Safe batch does not apply the verified final metadata URI");
requireValue(preparation?.buying?.fomo === routes(predictedToken).fomo, "Launch receipt Fomo route mismatch");
requireValue(safeBatch?.transactions?.length === 2, "Launch must be one two-call Safe batch");
requireValue(safeBatch.transactions[0]?.to?.toLowerCase() === preparation.deployment.launcher.toLowerCase(), "Safe batch does not launch first");
requireValue(safeBatch.transactions[1]?.to?.toLowerCase() === predictedToken.toLowerCase(), "Safe batch final metadata call targets the wrong token");
requireValue(safeBatch.transactions[1]?.data?.startsWith(toFunctionSelector("setContractURI(string)")), "Safe batch does not apply final contractURI second");

const observations = await verifySurfaceReceipt({ receipt, expectedAddress: predictedToken, assertMetadataFn: assertHoodMetadata });
let phase = "predeploy-prediction";
const deployed = argument("--token");
if (deployed) {
  const token = getAddress(deployed);
  requireValue(token.toLowerCase() === predictedToken.toLowerCase(), "Deployed token differs from prediction");
  const controllerValue = argument("--controller");
  requireValue(controllerValue, "--controller is required with --token");
  const controller = getAddress(controllerValue);
  const rpc = process.env.ROBINHOOD_MAINNET_RPC_URL?.trim();
  requireValue(rpc, "ROBINHOOD_MAINNET_RPC_URL is required for deployed verification");
  const chain = defineChain({ id: 4663, name: "Robinhood Chain", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [rpc] } } });
  const client = createPublicClient({ chain, transport: http(rpc) });
  requireValue(await client.getChainId() === 4663, "RPC is not Robinhood Chain");
  const tokenAbi = [
    { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
    { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
    { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
    { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
    { type: "function", name: "contractURI", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
    { type: "function", name: "image", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  ];
  const controllerAbi = [{ type: "function", name: "token", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] }];
  const [name, symbol, decimals, supply, contractURI, image, controllerToken] = await Promise.all([
    client.readContract({ address: token, abi: tokenAbi, functionName: "name" }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "symbol" }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "decimals" }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "totalSupply" }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "contractURI" }),
    client.readContract({ address: token, abi: tokenAbi, functionName: "image" }),
    client.readContract({ address: controller, abi: controllerAbi, functionName: "token" }),
  ]);
  requireValue(name === "VOIDCOIN" && symbol === "VOID" && decimals === 18, "Deployed immutable identity mismatch");
  requireValue(supply <= ORIGINAL_SUPPLY && supply + MAX_LAUNCH_DUST >= ORIGINAL_SUPPLY, "Deployed supply differs from the reviewed launch range");
  requireValue(contractURI === receipt.metadataURI && image === receipt.imageURI, "Deployed metadata surfaces differ from the verified receipt");
  requireValue(controllerToken.toLowerCase() === token.toLowerCase(), "Controller does not govern the deployed token");
  phase = "deployed-robinhood-mainnet";
}

console.log(JSON.stringify({ ok: true, phase, token: predictedToken, fomo: routes(predictedToken).fomo, metadataURI: receipt.metadataURI, imageURI: receipt.imageURI, observations }, null, 2));

import { readFile } from "node:fs/promises";
import path from "node:path";
import { getAddress } from "viem";
import { b20PredictionFromEnvironment } from "./b20-deployment-addresses.mjs";

const receipt = JSON.parse(await readFile(path.resolve("assets/genesis/b20-published.json"), "utf8"));
const prediction = await b20PredictionFromEnvironment();
if (receipt.metadataURI !== process.env.VOID_B20_CONTRACT_URI?.trim()) {
  throw new Error("VOID_B20_CONTRACT_URI does not match assets/genesis/b20-published.json");
}
if (getAddress(receipt.prediction?.token) !== prediction.token) {
  throw new Error("The predicted B20 address changed. Republish metadata after confirming the deployer nonce.");
}
if (receipt.prediction?.deployerNonce !== prediction.deployerNonce) {
  throw new Error("The deployer pending nonce changed. Do not broadcast this B20 deployment.");
}
if (receipt.prediction?.salt?.toLowerCase() !== prediction.salt.toLowerCase()) {
  throw new Error("VOID_B20_SALT changed. Do not broadcast this B20 deployment.");
}
if (receipt.metadata?.website !== "https://voidcoin.fun" || receipt.metadata?.external_url !== "https://voidcoin.fun") {
  throw new Error("B20 metadata must retain https://voidcoin.fun");
}
if (receipt.metadata?.standard !== "B20") {
  throw new Error("B20 metadata must expose the canonical standard field");
}
if (receipt.metadata?.launchpad !== "VOIDCOIN" || receipt.metadata?.launchpadUrl !== "https://voidcoin.fun") {
  throw new Error("B20 metadata must expose a truthful launch source and URL");
}
const routes = {
  website: "https://voidcoin.fun",
  baseApp: `https://base.app/coin/base-mainnet/${prediction.token}`,
  fomo: `https://fomo.family/tokens/base/${prediction.token}`,
  uniswap: `https://app.uniswap.org/explore/tokens/base/${prediction.token}`,
  dexScreener: `https://dexscreener.com/base/${prediction.token}`,
  explorer: `https://basescan.org/token/${prediction.token}`,
};
if (JSON.stringify(receipt.metadata?.links) !== JSON.stringify(routes) || receipt.metadata?.market_links?.length !== 6) {
  throw new Error("B20 metadata must expose both the Basecat-compatible links object and six typed market links");
}
if (getAddress(receipt.metadata?.contract_address) !== prediction.token) {
  throw new Error("B20 metadata contract_address does not match the predicted token");
}
console.log(JSON.stringify({ ok: true, metadataURI: receipt.metadataURI, prediction }, null, 2));

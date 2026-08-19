import { readFile } from "node:fs/promises";
import path from "node:path";
import { getAddress } from "viem";
import { predictionFromEnvironment } from "./deployment-addresses.mjs";

const WEBSITE = "https://voidcoin.fun";
const receiptPath = path.resolve("assets/genesis/published.json");
const receipt = JSON.parse(await readFile(receiptPath, "utf8"));
const prediction = await predictionFromEnvironment();

if (receipt.metadataURI !== process.env.INITIAL_TOKEN_URI?.trim()) {
  throw new Error("INITIAL_TOKEN_URI does not match assets/genesis/published.json");
}
if (getAddress(receipt.prediction?.token ?? "0x0000000000000000000000000000000000000000") !== prediction.token) {
  throw new Error("The predicted token address changed. Republish genesis metadata after confirming the deployer nonce.");
}
if (receipt.prediction?.deployerNonce !== prediction.deployerNonce) {
  throw new Error("The deployer pending nonce changed. Do not broadcast with this genesis metadata.");
}
if (receipt.metadata?.website !== WEBSITE || receipt.metadata?.external_url !== WEBSITE) {
  throw new Error(`Genesis metadata must use ${WEBSITE} as its permanent website`);
}
if (getAddress(receipt.metadata?.contract_address) !== prediction.token) {
  throw new Error("Genesis metadata contract_address does not match the predicted VOID token");
}

console.log(JSON.stringify({ ok: true, metadataURI: receipt.metadataURI, prediction }, null, 2));

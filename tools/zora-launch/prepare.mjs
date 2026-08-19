import { writeFile } from "node:fs/promises";
import { getAddress, isAddress } from "viem";
import { base } from "viem/chains";

const safe = process.env.SAFE_ADDRESS;
const metadataURI = process.env.ZORA_GENESIS_URI ?? process.env.INITIAL_TOKEN_URI;

if (!safe || !isAddress(safe)) throw new Error("SAFE_ADDRESS must be a valid Base address");
if (!metadataURI?.startsWith("ipfs://")) throw new Error("ZORA_GENESIS_URI must be a permanent ipfs:// URI");

const safeAddress = getAddress(safe);
if (process.env.ZORA_SKIP_METADATA_VALIDATION !== "true") {
  const cid = metadataURI.slice("ipfs://".length).replace(/^ipfs\//, "");
  const metadataResponse = await fetch(`https://magic.decentralized-content.com/ipfs/${cid}`);
  if (!metadataResponse.ok) throw new Error(`Zora metadata validation failed (${metadataResponse.status})`);
  const metadata = await metadataResponse.json();
  if (!metadata?.name || !metadata?.image || !metadata?.description) {
    throw new Error("Zora metadata must contain name, image, and description");
  }
}

const createResponse = await fetch("https://api-sdk.zora.engineering/create/content", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    creator: safeAddress,
    name: "VOIDCOIN",
    symbol: "VOID",
    metadata: { type: "RAW_URI", uri: metadataURI },
    currency: "ETH",
    chainId: base.id,
    startingMarketCap: "LOW",
    additionalOwners: [],
    payoutRecipientOverride: safeAddress,
  }),
});
if (!createResponse.ok) throw new Error(`Zora create-content request failed (${createResponse.status}): ${await createResponse.text()}`);
const result = await createResponse.json();
if (!result?.predictedCoinAddress || !Array.isArray(result.calls) || result.calls.length !== 1) {
  throw new Error("Zora returned incomplete launch calldata");
}

const receipt = {
  generatedAt: new Date().toISOString(),
  chainId: base.id,
  coinType: "Zora Content Coin",
  name: "VOIDCOIN",
  symbol: "VOID",
  metadataURI,
  currency: "ETH",
  startingMarketCap: "LOW",
  creator: safeAddress,
  payoutRecipient: safeAddress,
  predictedCoinAddress: getAddress(result.predictedCoinAddress),
  calls: result.calls.map((call) => ({
    to: getAddress(call.to),
    data: call.data,
    selector: call.data.slice(0, 10),
    value: String(call.value),
  })),
};

await writeFile(new URL("./zora-launch-calldata.json", import.meta.url), `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
const safeBatch = {
  version: "1.0",
  chainId: String(base.id),
  createdAt: Date.now(),
  meta: {
    name: "Create VOIDCOIN on Zora",
    description: `Create the Zora Content Coin at ${receipt.predictedCoinAddress}`,
    txBuilderVersion: "1.18.0",
    createdFromSafeAddress: safeAddress,
    createdFromOwnerAddress: "",
    checksum: "",
  },
  transactions: receipt.calls.map((call) => ({
    to: call.to,
    value: call.value,
    data: call.data,
    contractMethod: null,
    contractInputsValues: null,
  })),
};
await writeFile(
  new URL("./safe-transaction-builder.json", import.meta.url),
  `${JSON.stringify(safeBatch, null, 2)}\n`,
  { mode: 0o600 },
);
console.log(JSON.stringify(receipt, null, 2));
console.log("Safe Transaction Builder file: tools/zora-launch/safe-transaction-builder.json");

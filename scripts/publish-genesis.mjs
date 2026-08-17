import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { predictionFromEnvironment } from "./deployment-addresses.mjs";

const jwt = process.env.PINATA_JWT;
if (!jwt) throw new Error("PINATA_JWT is required");
const prediction = await predictionFromEnvironment();
const website = "https://voidcoin.fun";
const baseApp = `https://base.app/coin/base-mainnet/${prediction.token}`;
const fomo = `https://fomo.family/tokens/8453/${prediction.token}`;
const dexScreener = `https://dexscreener.com/base/${prediction.token}`;
const explorer = `https://basescan.org/token/${prediction.token}`;
const directory = path.resolve("assets/genesis");
const imageBytes = await readFile(path.join(directory, "voidcoin.png"));
const imageForm = new FormData();
imageForm.set("file", new Blob([imageBytes], { type: "image/png" }), "voidcoin.png");
imageForm.set("pinataMetadata", JSON.stringify({ name: "VOIDCOIN genesis image" }));
const imageResponse = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}` },
  body: imageForm,
});
if (!imageResponse.ok) throw new Error(`Image pin failed: ${imageResponse.status} ${await imageResponse.text()}`);
const imageResult = await imageResponse.json();
const imageURI = `ipfs://${imageResult.IpfsHash}`;
const metadata = {
  interop: { erc1046: true },
  name: "VOIDCOIN",
  symbol: "VOID",
  decimals: 18,
  description:
    "VOIDCOIN is a Base-native token whose identity is claimed by setting the highest permanent burn record. The first takeover burns 1,000,000 VOID; each challenger must burn at least 250,000 VOID more than the current record. Approved takeovers change the token's name, ticker, and image while https://voidcoin.fun remains permanent.",
  image: imageURI,
  images: [imageURI],
  icons: [imageURI],
  external_url: website,
  website,
  chain_id: 8453,
  contract_address: prediction.token,
  links: [
    { type: "website", label: "Website", url: website },
    { type: "base", label: "Base App", url: baseApp },
    { type: "fomo", label: "Fomo", url: fomo },
    { type: "dexscreener", label: "DEX Screener", url: dexScreener },
    { type: "explorer", label: "Contract", url: explorer },
  ],
  properties: {
    network: "Base Mainnet",
    chainId: 8453,
    contractAddress: prediction.token,
    website,
    baseApp,
    fomo,
    dexScreener,
    explorer,
  },
};
const metadataResponse = await fetch("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
  body: JSON.stringify({ pinataMetadata: { name: "VOIDCOIN genesis metadata" }, pinataContent: metadata }),
});
if (!metadataResponse.ok) throw new Error(`Metadata pin failed: ${metadataResponse.status} ${await metadataResponse.text()}`);
const metadataResult = await metadataResponse.json();
const receipt = {
  imageURI: metadata.image,
  metadataURI: `ipfs://${metadataResult.IpfsHash}`,
  metadata,
  prediction,
  publishedAt: new Date().toISOString(),
};
await writeFile(path.join(directory, "published.json"), `${JSON.stringify(receipt, null, 2)}\n`);
console.log(JSON.stringify(receipt, null, 2));

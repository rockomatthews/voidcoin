import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { b20PredictionFromEnvironment } from "./b20-deployment-addresses.mjs";

const jwt = process.env.PINATA_JWT;
if (!jwt) throw new Error("PINATA_JWT is required");
const prediction = await b20PredictionFromEnvironment();
const website = "https://voidcoin.fun";
const baseApp = `https://base.app/coin/base-mainnet/${prediction.token}`;
const fomo = `https://fomo.family/tokens/base/${prediction.token}`;
const dexScreener = `https://dexscreener.com/base/${prediction.token}`;
const explorer = `https://basescan.org/token/${prediction.token}`;
const uniswap = `https://app.uniswap.org/explore/tokens/base/${prediction.token}`;
const directory = path.resolve("assets/genesis");

const imageBytes = await readFile(path.join(directory, "voidcoin.png"));
const imageForm = new FormData();
imageForm.set("file", new Blob([imageBytes], { type: "image/png" }), "voidcoin.png");
imageForm.set("pinataMetadata", JSON.stringify({ name: "VOIDCOIN B20 genesis image" }));
const imageResponse = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}` },
  body: imageForm,
});
if (!imageResponse.ok) throw new Error(`Image pin failed: ${imageResponse.status} ${await imageResponse.text()}`);
const imageResult = await imageResponse.json();
const imageURI = `ipfs://${imageResult.IpfsHash}`;

const metadata = {
  interop: { erc1046: true, erc7572: true },
  name: "VOIDCOIN",
  symbol: "VOID",
  standard: "B20",
  launchpad: "VOIDCOIN",
  launchpadUrl: website,
  decimals: 18,
  description: "VOIDCOIN is a Base-native B20 whose identity is claimed by setting the highest permanent burn record. Approved record holders can transform the onchain name, ticker, and image while https://voidcoin.fun remains permanent.",
  image: imageURI,
  images: [imageURI],
  icons: [imageURI],
  external_url: website,
  website,
  chain_id: 8453,
  contract_address: prediction.token,
  token_standard: "B20 Asset",
  links: { website },
  properties: {
    network: "Base Mainnet",
    chainId: 8453,
    contractAddress: prediction.token,
    standard: "B20 Asset / ERC-20 / ERC-7572",
    website,
    baseApp,
    fomo,
    uniswap,
    dexScreener,
    explorer,
  },
};
const metadataResponse = await fetch("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
  body: JSON.stringify({ pinataMetadata: { name: "VOIDCOIN B20 genesis metadata" }, pinataContent: metadata }),
});
if (!metadataResponse.ok) throw new Error(`Metadata pin failed: ${metadataResponse.status} ${await metadataResponse.text()}`);
const metadataResult = await metadataResponse.json();
const receipt = {
  imageURI,
  metadataURI: `ipfs://${metadataResult.IpfsHash}`,
  metadata,
  prediction,
  publishedAt: new Date().toISOString(),
};
await writeFile(path.join(directory, "b20-published.json"), `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify(receipt, null, 2));

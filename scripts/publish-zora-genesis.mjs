import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const jwt = process.env.PINATA_JWT;
if (!jwt) throw new Error("PINATA_JWT is required");

const directory = path.resolve("assets/genesis");
const imageBytes = await readFile(path.join(directory, "voidcoin.png"));
const imageForm = new FormData();
imageForm.set("file", new Blob([imageBytes], { type: "image/png" }), "voidcoin.png");
imageForm.set("pinataMetadata", JSON.stringify({ name: "VOIDCOIN Zora genesis image" }));
const imageResponse = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}` },
  body: imageForm,
});
if (!imageResponse.ok) throw new Error(`Image pin failed: ${imageResponse.status} ${await imageResponse.text()}`);
const imageResult = await imageResponse.json();
const imageURI = `ipfs://${imageResult.IpfsHash}`;

const metadata = {
  name: "VOIDCOIN",
  symbol: "VOID",
  description: "VOIDCOIN is the Base coin anyone can try to control by setting a new permanent burn record. The first identity takeover burns 1,000,000 VOID. Every later record must beat both the prior record plus 250,000 VOID and the prior record plus 10%; the larger floor wins. Approved record holders transform the actual token name, ticker, and image while https://voidcoin.fun remains permanent.",
  image: imageURI,
  external_url: "https://voidcoin.fun",
  website: "https://voidcoin.fun",
  chain_id: 8453,
  platform: "Zora Content Coin",
  properties: {
    network: "Base Mainnet",
    chainId: 8453,
    website: "https://voidcoin.fun",
    zora: "https://zora.co",
  },
};
const metadataResponse = await fetch("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
  body: JSON.stringify({ pinataMetadata: { name: "VOIDCOIN Zora genesis metadata" }, pinataContent: metadata }),
});
if (!metadataResponse.ok) throw new Error(`Metadata pin failed: ${metadataResponse.status} ${await metadataResponse.text()}`);
const metadataResult = await metadataResponse.json();
const receipt = { imageURI, metadataURI: `ipfs://${metadataResult.IpfsHash}`, metadata, publishedAt: new Date().toISOString() };
await writeFile(path.join(directory, "zora-published.json"), `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify(receipt, null, 2));

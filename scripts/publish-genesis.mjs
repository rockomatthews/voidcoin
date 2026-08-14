import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const jwt = process.env.PINATA_JWT;
if (!jwt) throw new Error("PINATA_JWT is required");
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
const metadata = {
  name: "VOIDCOIN",
  symbol: "VOID",
  description: "The coin that changes its identity when a holder sets a new burn record.",
  image: `ipfs://${imageResult.IpfsHash}`,
  interop: { type: "erc20", version: "1.0.0" },
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
  publishedAt: new Date().toISOString(),
};
await writeFile(path.join(directory, "published.json"), `${JSON.stringify(receipt, null, 2)}\n`);
console.log(JSON.stringify(receipt, null, 2));

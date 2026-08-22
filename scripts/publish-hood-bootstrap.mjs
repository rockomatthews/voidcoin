import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const jwt = process.env.PINATA_JWT;
if (!jwt) throw new Error("PINATA_JWT is required");
const directory = path.resolve("assets/genesis");
const website = "https://voidcoin.fun";

const imageBytes = await readFile(path.join(directory, "voidcoin.png"));
const imageForm = new FormData();
imageForm.set("file", new Blob([imageBytes], { type: "image/png" }), "voidcoin.png");
imageForm.set("pinataMetadata", JSON.stringify({ name: "VOIDCOIN Hood genesis image" }));
const imageResponse = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}` },
  body: imageForm,
});
if (!imageResponse.ok) throw new Error(`Image pin failed: ${imageResponse.status} ${await imageResponse.text()}`);
const imageResult = await imageResponse.json();
const imageURI = `ipfs://${imageResult.IpfsHash}`;

// The token address depends on this URI. The address-bound final document is
// pinned after prediction and applied as transaction two of the launch batch.
const metadata = {
  name: "VOIDCOIN",
  symbol: "VOID",
  decimals: 18,
  image: imageURI,
  description: "VOIDCOIN is a fixed-supply Robinhood Chain token launched through hood.dev. Its website display skin can change only after an approved permanent burn; wallets and exchanges always show VOIDCOIN (VOID).",
  external_url: website,
  website,
  chain_id: 4663,
  launchpad: "hood.dev",
  stage: "bootstrap-address-prediction",
  properties: {
    network: "Robinhood Chain",
    chainId: 4663,
    immutableErc20Name: "VOIDCOIN",
    immutableErc20Symbol: "VOID",
  },
};
const metadataResponse = await fetch("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
  body: JSON.stringify({ pinataMetadata: { name: "VOIDCOIN Hood bootstrap metadata" }, pinataContent: metadata }),
});
if (!metadataResponse.ok) throw new Error(`Metadata pin failed: ${metadataResponse.status} ${await metadataResponse.text()}`);
const metadataResult = await metadataResponse.json();
const receipt = {
  status: "BOOTSTRAP_PINNED_NOT_LAUNCHED",
  imageURI,
  metadataURI: `ipfs://${metadataResult.IpfsHash}`,
  metadata,
  publishedAt: new Date().toISOString(),
};
await writeFile(path.join(directory, "hood-bootstrap-published.json"), `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify(receipt, null, 2));

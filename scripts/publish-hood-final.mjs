import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { getAddress } from "viem";

const jwt = process.env.PINATA_JWT;
if (!jwt) throw new Error("PINATA_JWT is required");
const directory = path.resolve("assets/genesis");
const preparationPath = path.resolve("tools/hood-launch/launch-preparation.json");
const preparation = JSON.parse(await readFile(preparationPath, "utf8"));
const token = getAddress(preparation?.deployment?.predictedToken);
const imageURI = preparation?.launch?.image;
if (typeof imageURI !== "string" || !imageURI.startsWith("ipfs://")) throw new Error("Launch preparation does not contain an IPFS image");

const website = "https://voidcoin.fun";
const links = {
  website,
  fomo: `https://fomo.family/tokens/robinhood/${token}`,
  hoodTerminal: "https://hood.dev",
  walletHelp: "https://robinhood.com/us/en/support/articles/robinhood-wallet/",
  dexScreener: `https://dexscreener.com/robinhood/${token}`,
  explorer: `https://robinhoodchain.blockscout.com/token/${token}`,
};
const metadata = {
  name: "VOIDCOIN",
  symbol: "VOID",
  image: imageURI,
  description: "VOIDCOIN is a fixed-supply Robinhood Chain token launched through hood.dev. Its website display skin can change only after an approved permanent burn; wallets and exchanges always show VOIDCOIN (VOID).",
  decimals: 18,
  external_url: website,
  website,
  chain_id: 4663,
  contract_address: token,
  links,
  market_links: [
    { type: "website", label: "Website", url: links.website },
    { type: "fomo", label: "Buy on Fomo", url: links.fomo },
    { type: "terminal", label: "hood.dev", url: links.hoodTerminal },
    { type: "dexscreener", label: "DEX Screener", url: links.dexScreener },
    { type: "explorer", label: "Contract", url: links.explorer },
    { type: "wallet-help", label: "Robinhood Wallet help", url: links.walletHelp },
  ],
  properties: {
    network: "Robinhood Chain",
    chainId: 4663,
    contractAddress: token,
    launchpad: "hood.dev",
    immutableErc20Name: "VOIDCOIN",
    immutableErc20Symbol: "VOID",
    displayName: "VOIDCOIN",
    displaySymbol: "VOID",
  },
};
const response = await fetch("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
  method: "POST",
  headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
  body: JSON.stringify({ pinataMetadata: { name: "VOIDCOIN Hood final genesis metadata" }, pinataContent: metadata }),
});
if (!response.ok) throw new Error(`Metadata pin failed: ${response.status} ${await response.text()}`);
const result = await response.json();
const receipt = {
  imageURI,
  metadataURI: `ipfs://${result.IpfsHash}`,
  metadata,
  prediction: {
    token,
    userSalt: preparation.launch.userSalt,
    bootstrapMetadataURI: preparation.launch.metadataURI,
  },
  publishedAt: new Date().toISOString(),
};
await writeFile(path.join(directory, "hood-published.json"), `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify(receipt, null, 2));

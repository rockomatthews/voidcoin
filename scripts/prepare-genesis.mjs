import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import sharp from "sharp";

const source = process.argv[2] ?? "/Users/rob/Desktop/voidCoinLogo.png";
const outputDirectory = path.resolve("assets/genesis");
const outputImage = path.join(outputDirectory, "voidcoin.png");
const outputMetadata = path.join(outputDirectory, "metadata.template.json");

await mkdir(outputDirectory, { recursive: true });
const sourceBytes = await readFile(source);
const image = sharp(sourceBytes, { animated: false, limitInputPixels: 2048 * 2048 });
const info = await image.metadata();
if (info.format !== "png" || !info.width || !info.height || info.width > 2048 || info.height > 2048) {
  throw new Error("Genesis artwork must be a PNG no larger than 2048 x 2048");
}

const cleaned = await image.png({ compressionLevel: 9, adaptiveFiltering: true }).toBuffer();
await writeFile(outputImage, cleaned);
const metadata = {
  name: "VOIDCOIN",
  symbol: "VOID",
  description: "The coin that changes its identity when a holder sets a new burn record.",
  image: "ipfs://IMAGE_CID",
  interop: { type: "erc20", version: "1.0.0" },
};
await writeFile(outputMetadata, `${JSON.stringify(metadata, null, 2)}\n`);

const digest = createHash("sha256").update(cleaned).digest("hex");
console.log(JSON.stringify({ source, outputImage, outputMetadata, width: info.width, height: info.height, bytes: cleaned.length, sha256: digest }, null, 2));

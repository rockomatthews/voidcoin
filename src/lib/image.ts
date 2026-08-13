import { createHash } from "node:crypto";
import sharp from "sharp";
import type { Hex } from "viem";

const MAX_BYTES = 2 * 1024 * 1024;
const MAX_DIMENSION = 2048;
const ALLOWED_FORMATS = new Set(["png", "jpeg", "gif"]);

export interface SanitizedImage {
  bytes: Buffer;
  contentType: "image/png" | "image/jpeg" | "image/gif";
  extension: "png" | "jpg" | "gif";
  hash: Hex;
  width: number;
  height: number;
}

export async function sanitizeImage(file: File): Promise<SanitizedImage> {
  if (file.size <= 0 || file.size > MAX_BYTES) throw new Error("Image must be between 1 byte and 2 MB");
  const input = Buffer.from(await file.arrayBuffer());
  const pipeline = sharp(input, { animated: true, limitInputPixels: MAX_DIMENSION * MAX_DIMENSION * 4 });
  const metadata = await pipeline.metadata();
  if (!metadata.format || !ALLOWED_FORMATS.has(metadata.format)) throw new Error("Only decoded PNG, JPEG, or GIF files are accepted");
  if (!metadata.width || !metadata.height || metadata.width > MAX_DIMENSION || metadata.height > MAX_DIMENSION) {
    throw new Error("Image dimensions must be no larger than 2048 × 2048");
  }

  let bytes: Buffer;
  let contentType: SanitizedImage["contentType"];
  let extension: SanitizedImage["extension"];
  if (metadata.format === "png") {
    bytes = await pipeline.rotate().png({ compressionLevel: 9 }).toBuffer();
    contentType = "image/png";
    extension = "png";
  } else if (metadata.format === "jpeg") {
    bytes = await pipeline.rotate().jpeg({ quality: 90, mozjpeg: true }).toBuffer();
    contentType = "image/jpeg";
    extension = "jpg";
  } else {
    bytes = await pipeline.gif({ effort: 7 }).toBuffer();
    contentType = "image/gif";
    extension = "gif";
  }

  const hash = `0x${createHash("sha256").update(bytes).digest("hex")}` as Hex;
  return { bytes, contentType, extension, hash, width: metadata.width, height: metadata.height };
}

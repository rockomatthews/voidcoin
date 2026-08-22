import { get } from "@vercel/blob";
import { configuredMarketVersion, configuredTokenAddress } from "@/lib/contract";
import { approvedHoodTokenMetadata, approvedTokenMetadata, OFFICIAL_WEBSITE } from "@/lib/token-metadata";

async function pinFile(bytes: Uint8Array, filename: string, contentType: string) {
  const jwt = process.env.PINATA_JWT;
  if (!jwt) throw new Error("PINATA_JWT is not configured");
  const form = new FormData();
  const body = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(body).set(bytes);
  form.append("file", new Blob([body], { type: contentType }), filename);
  form.append("pinataMetadata", JSON.stringify({ name: filename }));
  const response = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", { method: "POST", headers: { Authorization: `Bearer ${jwt}` }, body: form });
  if (!response.ok) throw new Error(`Pinata file upload failed (${response.status})`);
  return (await response.json()) as { IpfsHash: string };
}

async function pinJson(value: unknown, name: string) {
  const jwt = process.env.PINATA_JWT;
  if (!jwt) throw new Error("PINATA_JWT is not configured");
  const response = await fetch("https://api.pinata.cloud/pinning/pinJSONToIPFS", {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
    body: JSON.stringify({ pinataMetadata: { name }, pinataContent: value }),
  });
  if (!response.ok) throw new Error(`Pinata metadata upload failed (${response.status})`);
  return (await response.json()) as { IpfsHash: string };
}

export async function publishApprovedMetadata(input: { blobUrl: string; name: string; symbol: string; requestId: string }) {
  const contractAddress = configuredTokenAddress();
  if (!contractAddress) throw new Error("The production VOID token address is not configured");
  const stored = await get(input.blobUrl, { access: "private" });
  if (!stored || stored.statusCode !== 200) throw new Error("Private proposal image could not be read");
  const bytes = new Uint8Array(await new Response(stored.stream).arrayBuffer());
  const file = await pinFile(bytes, `voidcoin-${input.requestId}`, stored.blob.contentType ?? "application/octet-stream");
  const imageURI = `ipfs://${file.IpfsHash}`;
  const hood = configuredMarketVersion() === "hood";
  const metadataValue = hood
    ? approvedHoodTokenMetadata(input.name, input.symbol, imageURI, contractAddress)
    : approvedTokenMetadata(input.name, input.symbol, imageURI, contractAddress);
  const metadata = await pinJson(
    metadataValue,
    `voidcoin-${input.requestId}-metadata`,
  );
  return {
    metadataURI: `ipfs://${metadata.IpfsHash}`,
    imageURI,
    description: metadataValue.description,
    socials: JSON.stringify({ website: OFFICIAL_WEBSITE }),
  };
}

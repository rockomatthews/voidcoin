import { randomBytes } from "node:crypto";
import { put } from "@vercel/blob";
import { and, eq } from "drizzle-orm";
import { verifyMessage, zeroHash, type Address, type Hex } from "viem";
import { configuredChainId, configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { verifyWalletChallenge } from "@/lib/auth";
import { getPublicClient } from "@/lib/chain";
import { getDb, hasDatabase } from "@/lib/db";
import { proposalSubmissions, renameRequests } from "@/lib/db/schema";
import { sanitizeImage } from "@/lib/image";
import { createCommitment, parseStrategicBurn, proposalSchema } from "@/lib/proposal";

export async function GET(request: Request) {
  if (!hasDatabase()) return Response.json({ requests: [] });
  const wallet = new URL(request.url).searchParams.get("wallet")?.toLowerCase();
  if (!wallet) return Response.json({ error: "Wallet is required" }, { status: 400 });
  const rows = await getDb().select({ id: renameRequests.id, status: renameRequests.status, proposedName: renameRequests.proposedName, proposedSymbol: renameRequests.proposedSymbol, moderatorNote: renameRequests.moderatorNote, burnAmount: renameRequests.burnAmount, burnId: renameRequests.burnId, commitment: renameRequests.commitment, metadataURI: renameRequests.metadataURI }).from(renameRequests).where(eq(renameRequests.wallet, wallet));
  return Response.json({ requests: rows.map((row) => ({ ...row, burnId: row.burnId.toString(), burnAmount: row.burnAmount.toString() })) });
}

export async function POST(request: Request) {
  const contractAddress = configuredContractAddress();
  if (!contractAddress || !hasDatabase() || !process.env.BLOB_READ_WRITE_TOKEN) {
    return Response.json({ error: "Rename intake is not active until the Base Mainnet contract, Neon, and private Blob store are configured." }, { status: 503 });
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return Response.json({ error: "Invalid multipart request" }, { status: 400 });
  }

  const parsed = proposalSchema.safeParse({ wallet: form.get("wallet"), name: form.get("name"), symbol: form.get("symbol"), email: form.get("email") ?? "" });
  if (!parsed.success) return Response.json({ error: parsed.error.issues[0]?.message ?? "Invalid proposal" }, { status: 400 });
  const wallet = parsed.data.wallet as Address;
  const message = String(form.get("message") ?? "");
  const signature = String(form.get("signature") ?? "") as Hex;
  const challengeToken = String(form.get("challengeToken") ?? "");
  if (!verifyWalletChallenge(challengeToken, wallet) || !message.includes(`Challenge: ${challengeToken}`)) {
    return Response.json({ error: "Wallet challenge is invalid or expired" }, { status: 401 });
  }
  const verified = await verifyMessage({ address: wallet, message, signature }).catch(() => false);
  if (!verified) return Response.json({ error: "Wallet signature could not be verified" }, { status: 401 });

  const image = form.get("image");
  if (!(image instanceof File)) return Response.json({ error: "A token image is required" }, { status: 400 });

  try {
    const sanitized = await sanitizeImage(image);
    const client = getPublicClient();
    const [nextBurnId, nextBurnRequirement, maximumBurnAmount, slot] = await Promise.all([
      client.readContract({ address: contractAddress, abi: voidCoinAbi, functionName: "nextBurnId" }),
      client.readContract({ address: contractAddress, abi: voidCoinAbi, functionName: "nextBurnRequirement" }),
      client.readContract({ address: contractAddress, abi: voidCoinAbi, functionName: "maximumBurnAmount" }),
      client.readContract({ address: contractAddress, abi: voidCoinAbi, functionName: "activeSlot" }),
    ]);
    const isActive = slot.burner !== "0x0000000000000000000000000000000000000000";
    const isReplacement = isActive && slot.burner.toLowerCase() === wallet.toLowerCase();

    const burnId = isReplacement ? slot.burnId : nextBurnId;
    const requestedBurn = String(form.get("burnAmount") ?? "");
    const burnAmount = isReplacement
      ? slot.burnAmount
      : parseStrategicBurn(requestedBurn, nextBurnRequirement, maximumBurnAmount);
    const salt = `0x${randomBytes(32).toString("hex")}` as Hex;
    const commitment = createCommitment({ chainId: configuredChainId(), contractAddress, burnId, burner: wallet, burnAmount, name: parsed.data.name, symbol: parsed.data.symbol, imageHash: sanitized.hash, metadataURIHash: zeroHash, salt });
    const blob = await put(`requests/${wallet.toLowerCase()}/${burnId}.${sanitized.extension}`, sanitized.bytes, { access: "private", contentType: sanitized.contentType, addRandomSuffix: true, cacheControlMaxAge: 60 });
    const values = {
      wallet: wallet.toLowerCase(),
      burnAmount,
      contactEmail: parsed.data.email || null,
      proposedName: parsed.data.name,
      proposedSymbol: parsed.data.symbol,
      imageBlobUrl: blob.url,
      imageHash: sanitized.hash,
      imageWidth: sanitized.width,
      imageHeight: sanitized.height,
      salt,
      commitment,
      status: "awaiting_burn",
      updatedAt: new Date(),
    } as const;

    let requestId: string;
    if (isReplacement) {
      const [existing] = await getDb().select({ id: renameRequests.id }).from(renameRequests).where(and(eq(renameRequests.burnId, burnId), eq(renameRequests.wallet, wallet.toLowerCase()))).limit(1);
      if (!existing) return Response.json({ error: "The active burn has no matching private request" }, { status: 409 });
      await getDb().update(renameRequests).set(values).where(eq(renameRequests.id, existing.id));
      requestId = existing.id;
    } else {
      const [row] = await getDb().insert(renameRequests).values({ ...values, burnId }).returning({ id: renameRequests.id });
      requestId = row.id;
    }

    await getDb().insert(proposalSubmissions).values({ requestId, proposedName: parsed.data.name, proposedSymbol: parsed.data.symbol, imageBlobUrl: blob.url, imageHash: sanitized.hash, commitment });

    return Response.json({ requestId, burnId: burnId.toString(), burnAmount: burnAmount.toString(), commitment, mode: isReplacement ? "replace" : "burn" });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Proposal preparation failed" }, { status: 400 });
  }
}

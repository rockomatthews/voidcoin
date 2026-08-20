import { randomBytes } from "node:crypto";
import { put } from "@vercel/blob";
import { and, eq, inArray } from "drizzle-orm";
import { isAddress, verifyMessage, type Address, type Hex } from "viem";
import { configuredControllerAddress, configuredTokenAddress, voidSkinControllerAbi } from "@/lib/contract";
import { verifyWalletChallenge } from "@/lib/auth";
import { getPublicClient } from "@/lib/chain";
import { getDb, hasDatabase } from "@/lib/db";
import { proposalSubmissions, renameRequests } from "@/lib/db/schema";
import { sanitizeImage } from "@/lib/image";
import { parseStrategicBurn, proposalSchema } from "@/lib/proposal";

export async function GET(request: Request) {
  if (!hasDatabase()) return Response.json({ requests: [] });
  const wallet = new URL(request.url).searchParams.get("wallet")?.toLowerCase();
  const ids = new URL(request.url).searchParams.get("ids")?.split(",").filter((id) => /^[0-9a-f-]{36}$/i.test(id)).slice(0, 10) ?? [];
  if (!wallet || !isAddress(wallet) || ids.length === 0) return Response.json({ requests: [] });
  const rows = await getDb().select({ id: renameRequests.id, status: renameRequests.status, submissionMode: renameRequests.submissionMode, proposedName: renameRequests.proposedName, proposedSymbol: renameRequests.proposedSymbol, moderatorNote: renameRequests.moderatorNote, burnAmount: renameRequests.burnAmount, burnId: renameRequests.burnId, commitment: renameRequests.commitment, metadataURI: renameRequests.metadataURI }).from(renameRequests).where(and(eq(renameRequests.wallet, wallet), inArray(renameRequests.id, ids)));
  return Response.json({ requests: rows.map((row) => ({ ...row, burnId: row.burnId.toString(), burnAmount: row.burnAmount.toString() })) });
}

export async function POST(request: Request) {
  const contractAddress = configuredControllerAddress();
  const tokenAddress = configuredTokenAddress();
  if (!contractAddress || !tokenAddress || !hasDatabase() || !process.env.BLOB_READ_WRITE_TOKEN) {
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
    const [nextBurnId, nextBurnRequirement, maximumBurnAmount, slot, controllerToken] = await Promise.all([
      client.readContract({ address: contractAddress, abi: voidSkinControllerAbi, functionName: "nextBurnId" }),
      client.readContract({ address: contractAddress, abi: voidSkinControllerAbi, functionName: "nextBurnRequirement" }),
      client.readContract({ address: contractAddress, abi: voidSkinControllerAbi, functionName: "maximumBurnAmount" }),
      client.readContract({ address: contractAddress, abi: voidSkinControllerAbi, functionName: "activeSlot" }),
      client.readContract({ address: contractAddress, abi: voidSkinControllerAbi, functionName: "token" }),
    ]);
    if (controllerToken.toLowerCase() !== tokenAddress.toLowerCase()) throw new Error("Configured controller does not govern the configured B20 token");
    const isActive = slot.burner !== "0x0000000000000000000000000000000000000000";
    const isReplacement = isActive && slot.burner.toLowerCase() === wallet.toLowerCase();

    const burnId = isReplacement ? slot.burnId : nextBurnId;
    const requestedBurn = String(form.get("burnAmount") ?? "");
    const burnAmount = isReplacement
      ? slot.burnAmount
      : parseStrategicBurn(requestedBurn, nextBurnRequirement, maximumBurnAmount);
    const salt = `0x${randomBytes(32).toString("hex")}` as Hex;
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
      commitment: null,
      submissionMode: isReplacement ? "replace" : "burn",
      status: "draft",
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

    await getDb().insert(proposalSubmissions).values({ requestId, proposedName: parsed.data.name, proposedSymbol: parsed.data.symbol, imageBlobUrl: blob.url, imageHash: sanitized.hash, commitment: null });

    return Response.json({ requestId, status: "awaiting_moderation", message: "Proposal stored privately for moderation. No approval or burn is requested until its final IPFS metadata is pinned." });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Proposal preparation failed" }, { status: 400 });
  }
}

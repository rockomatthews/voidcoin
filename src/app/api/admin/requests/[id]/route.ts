import { eq } from "drizzle-orm";
import { encodeFunctionData, keccak256, toBytes } from "viem";
import { getAdminEmail, isSameOrigin } from "@/lib/auth";
import { configuredChainId, configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { getPublicClient } from "@/lib/chain";
import { getDb, hasDatabase } from "@/lib/db";
import { renameRequests } from "@/lib/db/schema";
import { publishApprovedMetadata } from "@/lib/pinata";
import { createCommitment } from "@/lib/proposal";

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!isSameOrigin(request)) return Response.json({ error: "Invalid request origin" }, { status: 403 });
  if (!(await getAdminEmail())) return Response.json({ error: "Unauthorized" }, { status: 401 });
  if (!hasDatabase()) return Response.json({ error: "Database is not configured" }, { status: 503 });
  const { id } = await params;
  const body = (await request.json().catch(() => null)) as { action?: string; note?: string } | null;
  const [proposal] = await getDb().select().from(renameRequests).where(eq(renameRequests.id, id)).limit(1);
  if (!proposal) return Response.json({ error: "Request not found" }, { status: 404 });

  if (body?.action === "request_changes") {
    await getDb().update(renameRequests).set({ status: "changes_requested", moderatorNote: body.note?.slice(0, 1000) ?? "Please submit an acceptable replacement.", updatedAt: new Date() }).where(eq(renameRequests.id, id));
    return Response.json({ ok: true });
  }

  if (body?.action === "approve") {
    const address = configuredContractAddress();
    if (!address) return Response.json({ error: "Contract is not configured" }, { status: 503 });
    try {
      const slot = await getPublicClient().readContract({ address, abi: voidCoinAbi, functionName: "activeSlot" });
      if (slot.burnId !== proposal.burnId || slot.burner.toLowerCase() !== proposal.wallet || slot.burnAmount !== proposal.burnAmount) {
        await getDb().update(renameRequests).set({ status: "superseded", updatedAt: new Date() }).where(eq(renameRequests.id, id));
        return Response.json({ error: "A higher burn record has superseded this proposal." }, { status: 409 });
      }
      if (!proposal.metadataURI) {
        const published = await publishApprovedMetadata({ blobUrl: proposal.imageBlobUrl, name: proposal.proposedName, symbol: proposal.proposedSymbol, requestId: proposal.id });
        const finalCommitment = createCommitment({
          chainId: configuredChainId(),
          contractAddress: address,
          burnId: proposal.burnId,
          burner: proposal.wallet as `0x${string}`,
          burnAmount: proposal.burnAmount,
          name: proposal.proposedName,
          symbol: proposal.proposedSymbol,
          imageHash: proposal.imageHash as `0x${string}`,
          metadataURIHash: keccak256(toBytes(published.metadataURI)),
          salt: proposal.salt as `0x${string}`,
        });
        await getDb().update(renameRequests).set({
          status: "changes_requested",
          metadataURI: published.metadataURI,
          commitment: finalCommitment,
          moderatorNote: "Content approved. Authorize the final IPFS metadata commitment from the burner wallet; no additional burn is required.",
          updatedAt: new Date(),
        }).where(eq(renameRequests.id, id));
        return Response.json({ ok: true, requiresBurnerAuthorization: true, commitment: finalCommitment, metadataURI: published.metadataURI });
      }
      if (slot.commitment.toLowerCase() !== proposal.commitment.toLowerCase()) {
        return Response.json({ error: "The burner must authorize the final IPFS metadata commitment before Safe approval." }, { status: 409 });
      }
      const lockCalldata = encodeFunctionData({ abi: voidCoinAbi, functionName: "lockRenameSlot", args: [proposal.burnId] });
      const calldata = encodeFunctionData({
        abi: voidCoinAbi,
        functionName: "approveRename",
        args: [proposal.burnId, proposal.proposedName, proposal.proposedSymbol, proposal.metadataURI, proposal.imageHash as `0x${string}`, proposal.salt as `0x${string}`],
      });
      await getDb().update(renameRequests).set({ status: "ready_for_safe", safeCalldata: calldata, updatedAt: new Date() }).where(eq(renameRequests.id, id));
      return Response.json({ ok: true, safeTransactions: [{ to: address, value: "0", data: lockCalldata, description: "Lock the record for six hours" }, { to: address, value: "0", data: calldata, description: "Apply the approved identity" }], metadataURI: proposal.metadataURI });
    } catch (error) {
      return Response.json({ error: error instanceof Error ? error.message : "Approval preparation failed" }, { status: 400 });
    }
  }

  return Response.json({ error: "Unsupported action" }, { status: 400 });
}

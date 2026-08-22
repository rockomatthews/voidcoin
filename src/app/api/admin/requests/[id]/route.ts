import { eq } from "drizzle-orm";
import { encodeFunctionData, keccak256, toBytes } from "viem";
import { getAdminEmail, isSameOrigin } from "@/lib/auth";
import { configuredChainId, configuredControllerAddress, configuredMarketVersion, configuredTokenAddress, hoodSkinControllerAbi, voidSkinControllerAbi } from "@/lib/contract";
import { getPublicClient } from "@/lib/chain";
import { getDb, hasDatabase } from "@/lib/db";
import { renameRequests } from "@/lib/db/schema";
import { publishApprovedMetadata } from "@/lib/pinata";
import { createCommitment, createHoodCommitment } from "@/lib/proposal";

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
    const address = configuredControllerAddress();
    const tokenAddress = configuredTokenAddress();
    const hood = configuredMarketVersion() === "hood";
    if (!address || !tokenAddress) return Response.json({ error: "Contract is not configured" }, { status: 503 });
    try {
      const client = getPublicClient();
      const [slot, nextBurnId, nextBurnRequirement, maximumBurnAmount, controllerToken] = await Promise.all([
        client.readContract({ address, abi: voidSkinControllerAbi, functionName: "activeSlot" }),
        client.readContract({ address, abi: voidSkinControllerAbi, functionName: "nextBurnId" }),
        client.readContract({ address, abi: voidSkinControllerAbi, functionName: "nextBurnRequirement" }),
        client.readContract({ address, abi: voidSkinControllerAbi, functionName: "maximumBurnAmount" }),
        client.readContract({ address, abi: voidSkinControllerAbi, functionName: "token" }),
      ]);
      if (controllerToken.toLowerCase() !== tokenAddress.toLowerCase()) {
        return Response.json({ error: "Configured controller does not govern the configured B20 token" }, { status: 503 });
      }

      if (proposal.status === "draft") {
        const validReplacement = proposal.submissionMode === "replace"
          && slot.burnId === proposal.burnId
          && slot.burner.toLowerCase() === proposal.wallet
          && slot.burnAmount === proposal.burnAmount;
        const validNewBurn = proposal.submissionMode === "burn"
          && nextBurnId === proposal.burnId
          && proposal.burnAmount >= nextBurnRequirement
          && proposal.burnAmount <= maximumBurnAmount;
        if (!validReplacement && !validNewBurn) {
          await getDb().update(renameRequests).set({ status: "superseded", updatedAt: new Date() }).where(eq(renameRequests.id, id));
          return Response.json({ error: "The burn level changed before moderation finished. Submit again; no tokens were approved or burned." }, { status: 409 });
        }
        const published = await publishApprovedMetadata({ blobUrl: proposal.imageBlobUrl, name: proposal.proposedName, symbol: proposal.proposedSymbol, requestId: proposal.id });
        const finalCommitment = hood
          ? createHoodCommitment({
              chainId: configuredChainId(), controllerAddress: address, burnId: proposal.burnId,
              burner: proposal.wallet as `0x${string}`, burnAmount: proposal.burnAmount,
              name: proposal.proposedName, symbol: proposal.proposedSymbol,
              image: published.imageURI, description: published.description, socials: published.socials,
              metadataURI: published.metadataURI, salt: proposal.salt as `0x${string}`,
            })
          : createCommitment({
              chainId: configuredChainId(), contractAddress: address, burnId: proposal.burnId,
              burner: proposal.wallet as `0x${string}`, burnAmount: proposal.burnAmount,
              name: proposal.proposedName, symbol: proposal.proposedSymbol,
              imageHash: proposal.imageHash as `0x${string}`,
              metadataURIHash: keccak256(toBytes(published.metadataURI)), salt: proposal.salt as `0x${string}`,
            });
        const hoodApprovalCalldata = hood ? encodeFunctionData({
          abi: hoodSkinControllerAbi,
          functionName: "approveRename",
          args: [proposal.burnId, {
            displayName: proposal.proposedName,
            displaySymbol: proposal.proposedSymbol,
            image: published.imageURI,
            description: published.description,
            socials: published.socials,
            metadataURI: published.metadataURI,
          }, proposal.salt as `0x${string}`],
        }) : null;
        await getDb().update(renameRequests).set({
          status: "awaiting_burn", metadataURI: published.metadataURI, commitment: finalCommitment,
          safeCalldata: hoodApprovalCalldata,
          moderatorNote: "Content approved and pinned. The burner may now execute the exact final commitment; the Safe will finalize within the 72-hour onchain window.", updatedAt: new Date(),
        }).where(eq(renameRequests.id, id));
        return Response.json({ ok: true, readyForBurn: true, commitment: finalCommitment, metadataURI: published.metadataURI });
      }

      if (proposal.status === "awaiting_burn") {
        return Response.json({ error: "The approved commitment has not been executed by the burner yet." }, { status: 409 });
      }
      if (proposal.status !== "pending_review") {
        return Response.json({ error: `Request status ${proposal.status} cannot be approved` }, { status: 409 });
      }

      if (slot.burnId !== proposal.burnId || slot.burner.toLowerCase() !== proposal.wallet || slot.burnAmount !== proposal.burnAmount) {
        await getDb().update(renameRequests).set({ status: "superseded", updatedAt: new Date() }).where(eq(renameRequests.id, id));
        return Response.json({ error: "A higher burn record has superseded this proposal." }, { status: 409 });
      }
      if (!proposal.metadataURI || !proposal.commitment) return Response.json({ error: "Approved metadata and its final commitment were not pinned before the burn" }, { status: 409 });
      if (slot.commitment.toLowerCase() !== proposal.commitment.toLowerCase()) {
        return Response.json({ error: "The burner must authorize the final IPFS metadata commitment before Safe approval." }, { status: 409 });
      }
      const lockCalldata = encodeFunctionData({ abi: voidSkinControllerAbi, functionName: "lockRenameSlot", args: [proposal.burnId] });
      const calldata = hood
        ? proposal.safeCalldata
        : encodeFunctionData({
            abi: voidSkinControllerAbi,
            functionName: "approveRename",
            args: [proposal.burnId, proposal.proposedName, proposal.proposedSymbol, proposal.metadataURI, proposal.imageHash as `0x${string}`, proposal.salt as `0x${string}`],
          });
      if (!calldata) return Response.json({ error: "V5 metadata calldata was not frozen before the burn" }, { status: 409 });
      await getDb().update(renameRequests).set({ status: "ready_for_safe", safeCalldata: calldata, updatedAt: new Date() }).where(eq(renameRequests.id, id));
      return Response.json({ ok: true, safeTransactions: [{ to: address, value: "0", data: lockCalldata, description: "Lock the record for six hours" }, { to: address, value: "0", data: calldata, description: "Apply the approved identity" }], metadataURI: proposal.metadataURI });
    } catch (error) {
      return Response.json({ error: error instanceof Error ? error.message : "Approval preparation failed" }, { status: 400 });
    }
  }

  return Response.json({ error: "Unsupported action" }, { status: 400 });
}

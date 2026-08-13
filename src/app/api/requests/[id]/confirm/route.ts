import { and, eq, inArray, ne } from "drizzle-orm";
import { decodeEventLog, isHash, type Hex } from "viem";
import { configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { getPublicClient } from "@/lib/chain";
import { getDb, hasDatabase } from "@/lib/db";
import { renameRequests } from "@/lib/db/schema";
import { sendModeratorAlert } from "@/lib/email";

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!hasDatabase()) return Response.json({ error: "Database is not configured" }, { status: 503 });
  const { id } = await params;
  const body = (await request.json().catch(() => null)) as { transactionHash?: string; mode?: "burn" | "replace" } | null;
  if (!body?.transactionHash || !isHash(body.transactionHash)) return Response.json({ error: "Valid transaction hash required" }, { status: 400 });

  const [proposal] = await getDb().select().from(renameRequests).where(eq(renameRequests.id, id)).limit(1);
  if (!proposal) return Response.json({ error: "Request not found" }, { status: 404 });
  const contractAddress = configuredContractAddress();
  if (!contractAddress) return Response.json({ error: "Contract is not configured" }, { status: 503 });

  try {
    const receipt = await getPublicClient().getTransactionReceipt({ hash: body.transactionHash as Hex });
    if (receipt.status !== "success") throw new Error("Burn transaction reverted");
    const expectedEvent = body.mode === "replace" ? "CommitmentReplaced" : "RenameBurned";
    const event = receipt.logs
      .filter((log) => log.address.toLowerCase() === contractAddress.toLowerCase())
      .map((log) => {
        try { return decodeEventLog({ abi: voidCoinAbi, data: log.data, topics: log.topics }); } catch { return null; }
      })
      .find((log) => log?.eventName === expectedEvent);
    if (!event || (event.eventName !== "RenameBurned" && event.eventName !== "CommitmentReplaced")) throw new Error(`${expectedEvent} event was not found`);
    const args = event.args;
    if (args.burner.toLowerCase() !== proposal.wallet || args.commitment.toLowerCase() !== proposal.commitment.toLowerCase() || args.burnId !== proposal.burnId) {
      throw new Error("Burn event does not match this private proposal");
    }
    if (event.eventName === "RenameBurned" && event.args.amount !== proposal.burnAmount) {
      throw new Error("Burn amount does not match this private proposal");
    }

    if (event.eventName === "RenameBurned") {
      await getDb().update(renameRequests).set({ status: "superseded", updatedAt: new Date() }).where(and(
        ne(renameRequests.id, id),
        inArray(renameRequests.status, ["pending_review", "changes_requested", "ready_for_safe"]),
      ));
    }
    await getDb().update(renameRequests).set({ transactionHash: body.transactionHash, status: "pending_review", updatedAt: new Date() }).where(eq(renameRequests.id, id));
    await sendModeratorAlert({ requestId: id, wallet: proposal.wallet, name: proposal.proposedName, symbol: proposal.proposedSymbol, burnId: proposal.burnId.toString() });
    return Response.json({ ok: true });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Burn verification failed" }, { status: 400 });
  }
}

import { desc, inArray } from "drizzle-orm";
import { AdminLogin } from "@/components/admin-login";
import { AdminPanel } from "@/components/admin-panel";
import { getAdminEmail } from "@/lib/auth";
import { getDb, hasDatabase } from "@/lib/db";
import { proposalSubmissions, renameRequests } from "@/lib/db/schema";

export const dynamic = "force-dynamic";

export default async function AdminPage() {
  const email = await getAdminEmail().catch(() => null);
  if (!email) return <main className="admin-shell"><AdminLogin /></main>;

  const rows = hasDatabase() ? await getDb().select().from(renameRequests).orderBy(desc(renameRequests.createdAt)).limit(50) : [];
  const submissions = rows.length ? await getDb().select().from(proposalSubmissions).where(inArray(proposalSubmissions.requestId, rows.map((row) => row.id))).orderBy(desc(proposalSubmissions.createdAt)) : [];
  const requests = rows.map((row) => ({
    id: row.id,
    burnId: row.burnId.toString(),
    wallet: row.wallet,
    proposedName: row.proposedName,
    proposedSymbol: row.proposedSymbol,
    status: row.status,
    transactionHash: row.transactionHash,
    expiresAt: row.expiresAt?.toISOString() ?? null,
    moderatorNote: row.moderatorNote,
    safeCalldata: row.safeCalldata,
    history: submissions.filter((submission) => submission.requestId === row.id).map((submission) => ({ name: submission.proposedName, symbol: submission.proposedSymbol, createdAt: submission.createdAt.toISOString() })),
  }));

  return <main className="admin-shell"><AdminPanel initialRequests={requests} /></main>;
}

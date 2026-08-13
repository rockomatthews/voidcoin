import { del } from "@vercel/blob";
import { and, eq, inArray, lt } from "drizzle-orm";
import { getDb, hasDatabase } from "@/lib/db";
import { proposalSubmissions, renameRequests } from "@/lib/db/schema";

export async function GET(request: Request) {
  const authorization = request.headers.get("authorization");
  if (!process.env.CRON_SECRET || authorization !== `Bearer ${process.env.CRON_SECRET}`) return Response.json({ error: "Unauthorized" }, { status: 401 });
  if (!hasDatabase() || !process.env.BLOB_READ_WRITE_TOKEN) return Response.json({ error: "Storage is not configured" }, { status: 503 });
  const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const rows = await getDb().select({ url: proposalSubmissions.imageBlobUrl }).from(proposalSubmissions).innerJoin(renameRequests, and(
    eq(proposalSubmissions.requestId, renameRequests.id),
    inArray(renameRequests.status, ["changes_requested", "expired"]),
    lt(proposalSubmissions.createdAt, cutoff),
  ));
  const urls = [...new Set(rows.map((row) => row.url))];
  if (urls.length) await del(urls);
  return Response.json({ deleted: urls.length, cutoff: cutoff.toISOString() });
}

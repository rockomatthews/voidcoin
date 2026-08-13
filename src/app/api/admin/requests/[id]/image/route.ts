import { get } from "@vercel/blob";
import { eq } from "drizzle-orm";
import { getAdminEmail } from "@/lib/auth";
import { getDb, hasDatabase } from "@/lib/db";
import { renameRequests } from "@/lib/db/schema";

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!(await getAdminEmail().catch(() => null))) return new Response("Unauthorized", { status: 401 });
  if (!hasDatabase()) return new Response("Database unavailable", { status: 503 });
  const { id } = await params;
  const [proposal] = await getDb().select({ imageBlobUrl: renameRequests.imageBlobUrl }).from(renameRequests).where(eq(renameRequests.id, id)).limit(1);
  if (!proposal) return new Response("Not found", { status: 404 });
  const stored = await get(proposal.imageBlobUrl, { access: "private" });
  if (!stored || stored.statusCode !== 200) return new Response("Not found", { status: 404 });
  return new Response(stored.stream, { headers: { "Content-Type": stored.blob.contentType ?? "application/octet-stream", "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff" } });
}

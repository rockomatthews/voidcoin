import { createHmac, timingSafeEqual } from "node:crypto";
import { getDb, hasDatabase } from "@/lib/db";
import { webhookReceipts } from "@/lib/db/schema";

function validSignature(rawBody: string, signature: string | null) {
  const key = process.env.ALCHEMY_WEBHOOK_SIGNING_KEY;
  if (!key || !signature) return false;
  const expected = createHmac("sha256", key).update(rawBody).digest("hex");
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function POST(request: Request) {
  const rawBody = await request.text();
  if (!validSignature(rawBody, request.headers.get("x-alchemy-signature"))) return Response.json({ error: "Invalid webhook signature" }, { status: 401 });
  if (!hasDatabase()) return Response.json({ error: "Database is not configured" }, { status: 503 });
  const payload = JSON.parse(rawBody) as { id?: string };
  const id = payload.id ?? request.headers.get("x-alchemy-webhook-id") ?? "";
  if (!id) return Response.json({ error: "Webhook id missing" }, { status: 400 });
  await getDb().insert(webhookReceipts).values({ id, provider: "alchemy", payload }).onConflictDoNothing();
  return Response.json({ received: true });
}

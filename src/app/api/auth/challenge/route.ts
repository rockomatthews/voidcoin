import { isAddress } from "viem";
import { createWalletChallenge } from "@/lib/auth";

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const wallet = typeof body === "object" && body !== null && "wallet" in body ? String(body.wallet) : "";
  if (!isAddress(wallet)) return Response.json({ error: "Invalid wallet" }, { status: 400 });
  try {
    return Response.json(createWalletChallenge(wallet));
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Authentication is not configured" }, { status: 503 });
  }
}

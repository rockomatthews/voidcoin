import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import type { Address } from "viem";

const CHALLENGE_TTL_SECONDS = 10 * 60;
const ADMIN_SESSION_TTL_SECONDS = 8 * 60 * 60;
const ADMIN_COOKIE = "voidcoin_admin";

interface SignedPayload {
  purpose: "wallet-challenge" | "admin-link" | "admin-session";
  subject: string;
  expiresAt: number;
  nonce: string;
}

function secret() {
  const value = process.env.AUTH_SECRET;
  if (!value || value.length < 32) throw new Error("AUTH_SECRET must be at least 32 characters");
  return value;
}

function encode(value: string) {
  return Buffer.from(value).toString("base64url");
}

function signBody(body: string) {
  return createHmac("sha256", secret()).update(body).digest("base64url");
}

function createToken(payload: SignedPayload) {
  const body = encode(JSON.stringify(payload));
  return `${body}.${signBody(body)}`;
}

function readToken(token: string, purpose: SignedPayload["purpose"]): SignedPayload | null {
  const [body, signature] = token.split(".");
  if (!body || !signature) return null;
  const expected = signBody(body);
  const receivedBuffer = Buffer.from(signature);
  const expectedBuffer = Buffer.from(expected);
  if (receivedBuffer.length !== expectedBuffer.length || !timingSafeEqual(receivedBuffer, expectedBuffer)) return null;

  try {
    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as SignedPayload;
    if (payload.purpose !== purpose || payload.expiresAt <= Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

export function createWalletChallenge(wallet: Address) {
  const expiresAt = Math.floor(Date.now() / 1000) + CHALLENGE_TTL_SECONDS;
  const token = createToken({ purpose: "wallet-challenge", subject: wallet.toLowerCase(), expiresAt, nonce: randomBytes(16).toString("hex") });
  const message = [
    "VOIDCOIN rename request",
    `Wallet: ${wallet.toLowerCase()}`,
    `Expires: ${expiresAt}`,
    `Challenge: ${token}`,
    "Signing does not spend tokens. The burn is a separate transaction.",
  ].join("\n");
  return { token, message, expiresAt };
}

export function verifyWalletChallenge(token: string, wallet: Address) {
  const payload = readToken(token, "wallet-challenge");
  return payload?.subject === wallet.toLowerCase();
}

export function createAdminLink(email: string) {
  return createToken({ purpose: "admin-link", subject: email.toLowerCase(), expiresAt: Math.floor(Date.now() / 1000) + 15 * 60, nonce: randomBytes(16).toString("hex") });
}

export function verifyAdminLink(token: string) {
  return readToken(token, "admin-link");
}

export async function setAdminSession(email: string) {
  const token = createToken({ purpose: "admin-session", subject: email.toLowerCase(), expiresAt: Math.floor(Date.now() / 1000) + ADMIN_SESSION_TTL_SECONDS, nonce: randomBytes(16).toString("hex") });
  const store = await cookies();
  store.set(ADMIN_COOKIE, token, { httpOnly: true, sameSite: "strict", secure: process.env.NODE_ENV === "production", maxAge: ADMIN_SESSION_TTL_SECONDS, path: "/" });
}

export async function getAdminEmail() {
  const store = await cookies();
  const token = store.get(ADMIN_COOKIE)?.value;
  const payload = token ? readToken(token, "admin-session") : null;
  const allowed = process.env.ADMIN_EMAIL?.toLowerCase();
  return payload && allowed && payload.subject === allowed ? payload.subject : null;
}

export function isSameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  return Boolean(origin && origin === new URL(request.url).origin);
}

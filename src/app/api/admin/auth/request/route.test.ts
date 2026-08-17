import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  send: vi.fn(),
}));

vi.mock("@/lib/auth", () => ({
  createAdminLink: () => "signed-token",
  isSameOrigin: () => true,
}));
vi.mock("@/lib/site", () => ({ getSiteUrl: () => "https://voidcoin.fun" }));
vi.mock("resend", () => ({
  Resend: class {
    emails = { send: mocks.send };
  },
}));

import { POST } from "./route";

const originalAdminEmail = process.env.ADMIN_EMAIL;
const originalResendKey = process.env.RESEND_API_KEY;
const originalEmailFrom = process.env.EMAIL_FROM;

function request(email: string) {
  return new Request("https://voidcoin.fun/api/admin/auth/request", {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: "https://voidcoin.fun" },
    body: JSON.stringify({ email }),
  });
}

beforeEach(() => {
  mocks.send.mockReset();
  process.env.ADMIN_EMAIL = "moderator@example.com";
  process.env.RESEND_API_KEY = "re_test";
  process.env.EMAIL_FROM = "VOIDCOIN <moderator@voidcoin.fun>";
});

afterAll(() => {
  process.env.ADMIN_EMAIL = originalAdminEmail;
  process.env.RESEND_API_KEY = originalResendKey;
  process.env.EMAIL_FROM = originalEmailFrom;
});

describe("moderator magic-link delivery", () => {
  it("reports a provider rejection instead of claiming the link was sent", async () => {
    mocks.send.mockResolvedValue({ data: null, error: { message: "domain is not verified" } });
    const response = await POST(request("moderator@example.com"));

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toEqual({
      error: "Moderator email delivery failed. Check the Resend sender and domain.",
    });
  });

  it("returns success only after Resend supplies a message id", async () => {
    mocks.send.mockResolvedValue({ data: { id: "email_123" }, error: null });
    const response = await POST(request("moderator@example.com"));

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ ok: true });
  });

  it("keeps unauthorized address checks non-disclosing", async () => {
    const response = await POST(request("stranger@example.com"));

    expect(response.status).toBe(200);
    expect(mocks.send).not.toHaveBeenCalled();
  });
});

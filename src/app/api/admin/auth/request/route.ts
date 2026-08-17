import { createAdminLink, isSameOrigin } from "@/lib/auth";
import { getSiteUrl } from "@/lib/site";
import { Resend } from "resend";

export async function POST(request: Request) {
  if (!isSameOrigin(request)) return Response.json({ error: "Invalid request origin" }, { status: 403 });
  const body = (await request.json().catch(() => null)) as { email?: string } | null;
  const email = body?.email?.trim().toLowerCase();
  const allowed = process.env.ADMIN_EMAIL?.toLowerCase();
  if (!email || !allowed || email !== allowed) return Response.json({ ok: true });
  try {
    const token = createAdminLink(email);
    const url = `${getSiteUrl()}/api/admin/auth/verify?token=${encodeURIComponent(token)}`;
    if (process.env.RESEND_API_KEY) {
      const resend = new Resend(process.env.RESEND_API_KEY);
      const { data, error } = await resend.emails.send(
        {
          from: process.env.EMAIL_FROM ?? "VOIDCOIN <onboarding@resend.dev>",
          to: email,
          subject: "VOIDCOIN moderator sign-in",
          html: `<p>This link expires in 15 minutes.</p><p><a href="${url}">Open the moderation chamber</a></p>`,
        },
        { headers: { "Idempotency-Key": `voidcoin-admin-${token.slice(0, 24)}` } },
      );
      if (error || !data?.id) {
        console.error("VOIDCOIN moderator sign-in delivery rejected", error);
        return Response.json({ error: "Moderator email delivery failed. Check the Resend sender and domain." }, { status: 503 });
      }
      console.info("VOIDCOIN moderator sign-in accepted", { resendEmailId: data.id });
      return Response.json({ ok: true });
    }
    if (process.env.NODE_ENV !== "production") return Response.json({ ok: true, previewUrl: url });
    return Response.json({ error: "Email delivery is not configured" }, { status: 503 });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Sign-in failed" }, { status: 503 });
  }
}

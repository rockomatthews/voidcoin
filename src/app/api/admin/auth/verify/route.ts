import { verifyAdminLink, setAdminSession } from "@/lib/auth";
import { getSiteUrl } from "@/lib/site";

export async function GET(request: Request) {
  const token = new URL(request.url).searchParams.get("token") ?? "";
  const payload = verifyAdminLink(token);
  const allowed = process.env.ADMIN_EMAIL?.toLowerCase();
  if (!payload || !allowed || payload.subject !== allowed) return Response.redirect(`${getSiteUrl()}/admin?error=invalid-link`);
  await setAdminSession(payload.subject);
  return Response.redirect(`${getSiteUrl()}/admin`);
}

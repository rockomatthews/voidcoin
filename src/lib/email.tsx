import { Resend } from "resend";
import { ModeratorAlertEmail } from "@/emails/moderator-alert";
import { getSiteUrl, shortAddress } from "./site";

function getResend() {
  const key = process.env.RESEND_API_KEY;
  return key ? new Resend(key) : null;
}

export async function sendModeratorAlert(input: { requestId: string; wallet: string; name: string; symbol: string; burnId: string }) {
  const resend = getResend();
  const to = process.env.ADMIN_EMAIL;
  if (!resend || !to) return { skipped: true as const };

  return resend.emails.send(
    {
      from: process.env.EMAIL_FROM ?? "VOIDCOIN <onboarding@resend.dev>",
      to,
      subject: `VOIDCOIN rename review · ${input.name} ($${input.symbol})`,
      react: ModeratorAlertEmail({
        name: input.name,
        symbol: input.symbol,
        burner: shortAddress(input.wallet),
        burnId: input.burnId,
        reviewUrl: `${getSiteUrl()}/admin?request=${input.requestId}`,
      }),
    },
    { headers: { "Idempotency-Key": `voidcoin-review-${input.requestId}` } },
  );
}

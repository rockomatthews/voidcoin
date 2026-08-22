import { DynamicIdentityHero } from "@/components/dynamic-identity-hero";
import { IdentityGallery } from "@/components/identity-gallery";
import { ProtocolStats } from "@/components/protocol-stats";
import { configuredMarketVersion } from "@/lib/contract";

export default function Home() {
  const hood = configuredMarketVersion() === "hood";
  return (
    <main className="void-page">
      <DynamicIdentityHero />

      <ProtocolStats />

      <IdentityGallery />

      <footer className="void-footer"><span>SKIN MUTABLE / {hood ? "TOKEN FIXED: VOIDCOIN (VOID) / ROBINHOOD CHAIN" : "BASE MAINNET"}</span><a href="/admin">MODERATOR</a></footer>
    </main>
  );
}

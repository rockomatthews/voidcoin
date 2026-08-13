import { BurnTerminal } from "@/components/burn-terminal";
import { DynamicIdentityHero } from "@/components/dynamic-identity-hero";
import { IdentityGallery } from "@/components/identity-gallery";
import { ProtocolStats } from "@/components/protocol-stats";

export default function Home() {
  return (
    <main className="void-page">
      <DynamicIdentityHero />

      <ProtocolStats />

      <IdentityGallery />

      <details className="request-drawer">
        <summary>REQUEST THE NEXT IDENTITY <span>+</span></summary>
        <BurnTerminal />
      </details>

      <footer className="void-footer"><span>IDENTITY MUTABLE / BASE MAINNET</span><a href="/admin">MODERATOR</a></footer>
    </main>
  );
}

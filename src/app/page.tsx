import Image from "next/image";
import { BurnTerminal } from "@/components/burn-terminal";
import { BuyVoid } from "@/components/buy-void";
import { IdentityGallery } from "@/components/identity-gallery";
import { LiveState } from "@/components/live-state";
import { WalletButton } from "@/components/wallet-button";

export default function Home() {
  return (
    <main className="void-page">
      <nav className="void-nav" aria-label="Primary navigation">
        <a className="void-mark" href="#top" aria-label="VOIDCOIN home"><span><Image src="/voidcoin-logo.png" alt="" width={30} height={30} /></span> VOIDCOIN</a>
        <WalletButton />
      </nav>

      <section className="void-hero" id="top" aria-labelledby="void-title">
        <div className="void-orbit" aria-hidden="true"><i /><i /><i /><Image src="/voidcoin-logo.png" alt="" width={92} height={92} priority /></div>
        <p className="void-label">OUTBURN THE LAST HOLDER. TAKE CONTROL.</p>
        <h1 id="void-title"><strong>VOID</strong><span>THE IDENTITY NEVER STAYS STILL</span></h1>
        <p className="void-message">Buy VOID, beat the all-time burn record by at least <b>1,000,000</b>, and claim the right to request a new <b>name</b>, <b>ticker</b>, and <b>picture</b>.</p>
        <LiveState />
        <div className="void-attributes" aria-label="Changeable token identity"><span>NAME</span><span>TICKER</span><span>PICTURE</span></div>
        <p className="void-note">Every burn is irreversible. A higher record can take control before approval. Every identity change requires moderation.</p>
      </section>

      <BuyVoid />

      <IdentityGallery />

      <details className="request-drawer">
        <summary>REQUEST THE NEXT IDENTITY <span>+</span></summary>
        <BurnTerminal />
      </details>

      <footer className="void-footer"><span>VOIDCOIN / BASE</span><a href="/admin">MODERATOR</a></footer>
    </main>
  );
}

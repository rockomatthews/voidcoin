import { BurnTerminal } from "@/components/burn-terminal";
import { IdentityGallery } from "@/components/identity-gallery";
import { WalletButton } from "@/components/wallet-button";

export default function Home() {
  return (
    <main className="void-page">
      <nav className="void-nav" aria-label="Primary navigation">
        <a className="void-mark" href="#top" aria-label="VOIDCOIN home"><span>VØ</span> VOIDCOIN</a>
        <WalletButton />
      </nav>

      <section className="void-hero" id="top" aria-labelledby="void-title">
        <div className="void-orbit" aria-hidden="true"><i /><i /><i /><b>VØ</b></div>
        <p className="void-label">THE PRICE OF A NEW IDENTITY</p>
        <h1 id="void-title"><strong>1,000,000</strong><span>VOID</span></h1>
        <p className="void-message">Own and permanently burn this amount to request a new <b>name</b>, <b>ticker</b>, and <b>picture</b>.</p>
        <div className="void-attributes" aria-label="Changeable token identity"><span>NAME</span><span>TICKER</span><span>PICTURE</span></div>
        <p className="void-note">Every burn is irreversible. Every change requires approval.</p>
      </section>

      <IdentityGallery />

      <details className="request-drawer">
        <summary>REQUEST THE NEXT IDENTITY <span>+</span></summary>
        <BurnTerminal />
      </details>

      <footer className="void-footer"><span>VOIDCOIN / BASE</span><a href="/admin">MODERATOR</a></footer>
    </main>
  );
}

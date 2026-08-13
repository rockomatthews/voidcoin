import { BurnTerminal } from "@/components/burn-terminal";
import { IdentityReactor } from "@/components/identity-reactor";
import { LiveState } from "@/components/live-state";
import { WalletButton } from "@/components/wallet-button";

const archive = [
  { id: "000", name: "VOIDCOIN", ticker: "VOID", wallet: "GENESIS", movement: "AWAITING MARKET", accent: "cyan" },
  { id: "001", name: "UNWRITTEN", ticker: "—", wallet: "NEXT BURNER", movement: "LOCKED", accent: "violet" },
  { id: "002", name: "UNWRITTEN", ticker: "—", wallet: "THE VOID", movement: "LOCKED", accent: "magenta" },
];

export default function Home() {
  return (
    <main>
      <nav className="site-nav" aria-label="Primary navigation">
        <a className="wordmark" href="#top" aria-label="VOIDCOIN home"><span>VØ</span> VOIDCOIN</a>
        <div className="nav-links"><a href="#protocol">PROTOCOL</a><a href="#archive">ARCHIVE</a><a href="#burn">BURN</a></div>
        <WalletButton />
      </nav>

      <section className="hero" id="top">
        <div className="hero-copy">
          <div className="protocol-badge"><i /> BASE / IDENTITY PROTOCOL / TEST GATE</div>
          <h1><span>BURN THE OLD.</span><br />AUTHOR THE <em>NEXT.</em></h1>
          <p>VOIDCOIN is a token with a destructible identity. Burn exactly <strong>1,000,000 VOID</strong>, submit a private skin, and—after safety review—rewrite its name, ticker, and face onchain.</p>
          <div className="hero-actions"><a className="primary-action" href="#burn">ENTER THE CHAMBER</a><a className="text-action" href="#protocol">READ THE PROTOCOL <span>↘</span></a></div>
          <div className="chain-stamp"><span>NETWORK</span><strong>BASE</strong><span>MECHANIC</span><strong>FIXED BURN</strong></div>
        </div>
        <IdentityReactor />
      </section>

      <section className="live-section" aria-labelledby="live-heading">
        <div className="section-index">01 / LIVE SIGNAL</div>
        <h2 className="section-title" id="live-heading">THE TOKEN IS THE CANVAS.</h2>
        <LiveState />
      </section>

      <section className="protocol-section" id="protocol" aria-labelledby="protocol-heading">
        <div className="section-index">02 / THE PROTOCOL</div>
        <div className="protocol-intro"><h2 className="section-title" id="protocol-heading">IDENTITY HAS<br />A BURN RATE.</h2><p>The website brand remains VOIDCOIN. Each approved burner changes only the token&apos;s public skin. Every attempt destroys 0.1% of genesis supply forever.</p></div>
        <ol className="sequence">
          <li><span>01</span><div><strong>COMPOSE IN PRIVATE</strong><p>Sign in with a Base wallet. Your text and sanitized image stay offchain and private during review.</p></div></li>
          <li><span>02</span><div><strong>DESTROY TO CLAIM</strong><p>A cryptographic commitment binds your proposal to your wallet, this chain, and the next burn ID.</p></div></li>
          <li><span>03</span><div><strong>72-HOUR WINDOW</strong><p>The active burner can replace a rejected proposal without paying again until the slot expires.</p></div></li>
          <li><span>04</span><div><strong>SAFE EXECUTION</strong><p>Approval publishes the clean asset to IPFS and prepares an exact transaction for the owner Safe.</p></div></li>
        </ol>
      </section>

      <section className="archive-section" id="archive" aria-labelledby="archive-heading">
        <div className="section-index">03 / ARCHIVE OF FACES</div>
        <div className="archive-head"><h2 className="section-title" id="archive-heading">EVERY FACE<br />LEAVES A SCAR.</h2><p>Each approved identity will remain indexed here from contract events, with burner provenance, transaction links, and price movement.</p></div>
        <div className="archive-deck">
          {archive.map((face) => <article className={`face-card face-${face.accent}`} key={face.id}><div className="face-visual"><span>SKIN / {face.id}</span><b>{face.id === "000" ? "VØ" : "?"}</b></div><div className="face-info"><small>{face.wallet}</small><h3>{face.name}</h3><strong>${face.ticker}</strong><span>{face.movement}</span></div></article>)}
        </div>
      </section>

      <section className="burn-section" id="burn" aria-labelledby="burn-heading">
        <div className="section-index">04 / RENAME TERMINAL</div>
        <div className="burn-intro"><h2 className="section-title" id="burn-heading">MAKE YOUR<br />MARK PERMANENT.</h2><p>This interface is launch-gated. It activates only after a complete Base Sepolia lifecycle, security clearance, verified Safe ownership, and explicit production approval.</p></div>
        <BurnTerminal />
      </section>

      <section className="event-stream" aria-label="Protocol event stream">
        <div className="stream-head"><span>ONCHAIN EVENT STREAM</span><span className="stream-live">● AWAITING SEPOLIA</span></div>
        <div className="stream-line"><time>GENESIS</time><code>VOIDCOIN_INITIALIZED</code><span>1,000,000,000 VOID / RENAME SLOTS PAUSED</span></div>
        <div className="stream-line muted"><time>—</time><code>NEXT_EVENT</code><span>RENAME_BURNED → COMMITMENT HASH → 72H DEADLINE</span></div>
      </section>

      <footer><a className="wordmark" href="#top"><span>VØ</span> VOIDCOIN</a><p>Token metadata may remain cached by wallets, explorers, exchanges, and market-data providers after an approved change.</p><div><a href="/admin">MODERATOR</a><a href="https://base.org" target="_blank" rel="noreferrer">BUILT ON BASE ↗</a></div></footer>
    </main>
  );
}

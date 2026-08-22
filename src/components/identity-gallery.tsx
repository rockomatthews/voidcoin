"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { shortAddress } from "@/lib/site";
import { liveIdentityFromContract } from "@/lib/token-metadata";
import { configuredMarketVersion } from "@/lib/contract";

interface Identity {
  burnId: string;
  name: string;
  symbol: string;
  image: string | null;
  burner: string;
  transactionHash: string | null;
}

const preview: Identity[] = [{ burnId: "0", name: "VOIDCOIN", symbol: "VOID", image: "/voidcoin-logo.png", burner: "GENESIS", transactionHash: null }];

export function IdentityGallery() {
  const hood = configuredMarketVersion() === "hood";
  const [current, setCurrent] = useState<Identity>(preview[0]);
  const [immutableIdentity, setImmutableIdentity] = useState({ name: "VOIDCOIN", symbol: "VOID" });
  const [identities, setIdentities] = useState<Identity[]>([]);

  useEffect(() => {
    const controller = new AbortController();
    const load = () => Promise.all([
        fetch("/api/state", { signal: controller.signal }).then((response) => response.ok ? response.json() : Promise.reject(new Error("State unavailable"))),
        fetch("/api/archive", { signal: controller.signal }).then((response) => response.ok ? response.json() : Promise.reject(new Error("Archive unavailable"))),
      ])
        .then(([state, archive]: [{ name: string; symbol: string; immutableName?: string; immutableSymbol?: string; image: string | null }, { identities: Identity[] }]) => {
          const history = archive.identities ?? [];
          const archiveMatchesCurrent = history[0]?.name === state.name && history[0]?.symbol === state.symbol;
          const liveIdentity = liveIdentityFromContract(state, history[0]);
          const nextCurrent: Identity = { burnId: "current", ...liveIdentity, burner: "CURRENT", transactionHash: null };
          const archiveHasCurrent = archiveMatchesCurrent && (!nextCurrent.image || history[0]?.image === nextCurrent.image);
          setCurrent(nextCurrent);
          setImmutableIdentity({ name: state.immutableName ?? state.name, symbol: state.immutableSymbol ?? state.symbol });
          setIdentities(archiveHasCurrent ? history.slice(1) : history);
        })
        .catch(() => undefined);
    void load();
    const interval = window.setInterval(load, 10_000);
    return () => { controller.abort(); window.clearInterval(interval); };
  }, []);

  return (
    <section className="identity-section" aria-labelledby="identity-heading">
      <div className="current-identity">
        <div className="identity-image">
          {current.image ? <Image src={current.image} alt={`${current.name} token identity`} fill sizes="(max-width: 700px) 82vw, 420px" unoptimized={current.image.startsWith("http")} /> : <span>VØ</span>}
        </div>
        <div className="identity-copy"><p>CURRENT DISPLAY SKIN</p><h2>{current.name}</h2><strong>${current.symbol}</strong>{hood ? <small>WALLET / EXCHANGE TOKEN: {immutableIdentity.name} (${immutableIdentity.symbol})</small> : null}</div>
      </div>

      <div className="archive-heading"><p>PREVIOUS IDENTITIES</p><h2 id="identity-heading">THE FACES<br />LEFT BEHIND.</h2></div>
      <div className="identity-grid">
        {identities.length ? identities.map((identity, index) => (
          <article className="identity-card" key={`${identity.burnId}-${identity.transactionHash ?? "genesis"}`}>
            <div className="identity-card-image">{identity.image ? <Image src={identity.image} alt={`${identity.name} archived token identity`} fill sizes="(max-width: 700px) 82vw, 320px" unoptimized={identity.image.startsWith("http")} /> : <span>VØ</span>}<i>#{String(identities.length - index - 1).padStart(3, "0")}</i></div>
            <div className="identity-card-copy"><h3>{identity.name}</h3><strong>${identity.symbol}</strong><small>{identity.burner === "GENESIS" ? "GENESIS" : shortAddress(identity.burner)}</small>{identity.transactionHash ? <a href={hood ? `https://robinhoodchain.blockscout.com/tx/${identity.transactionHash}` : `https://basescan.org/tx/${identity.transactionHash}`} target="_blank" rel="noreferrer">TX ↗</a> : null}</div>
          </article>
        )) : <div className="stats-empty">THE FIRST FORMER IDENTITY WILL APPEAR HERE.</div>}
      </div>
    </section>
  );
}

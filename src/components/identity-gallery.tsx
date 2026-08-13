"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { shortAddress } from "@/lib/site";

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
  const [identities, setIdentities] = useState(preview);

  useEffect(() => {
    const controller = new AbortController();
    fetch("/api/archive", { signal: controller.signal })
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("Archive unavailable")))
      .then((value: { identities: Identity[] }) => setIdentities(value.identities.length ? value.identities : preview))
      .catch(() => undefined);
    return () => controller.abort();
  }, []);

  const current = identities[0];
  return (
    <section className="identity-section" aria-labelledby="identity-heading">
      <div className="current-identity">
        <div className="identity-image">
          {current.image ? <Image src={current.image} alt={`${current.name} token identity`} fill sizes="(max-width: 700px) 82vw, 420px" unoptimized={current.image.startsWith("http")} /> : <span>VØ</span>}
        </div>
        <div className="identity-copy"><p>CURRENT IDENTITY</p><h2>{current.name}</h2><strong>${current.symbol}</strong></div>
      </div>

      <div className="archive-heading"><p>PREVIOUS IDENTITIES</p><h2 id="identity-heading">THE FACES<br />LEFT BEHIND.</h2></div>
      <div className="identity-grid">
        {identities.map((identity, index) => (
          <article className="identity-card" key={`${identity.burnId}-${identity.transactionHash ?? "genesis"}`}>
            <div className="identity-card-image">{identity.image ? <Image src={identity.image} alt={`${identity.name} archived token identity`} fill sizes="(max-width: 700px) 82vw, 320px" unoptimized={identity.image.startsWith("http")} /> : <span>VØ</span>}<i>#{String(identities.length - index - 1).padStart(3, "0")}</i></div>
            <div className="identity-card-copy"><h3>{identity.name}</h3><strong>${identity.symbol}</strong><small>{identity.burner === "GENESIS" ? "GENESIS" : shortAddress(identity.burner)}</small>{identity.transactionHash ? <a href={`https://${process.env.NEXT_PUBLIC_CHAIN_ID === "8453" ? "" : "sepolia."}basescan.org/tx/${identity.transactionHash}`} target="_blank" rel="noreferrer">TX ↗</a> : null}</div>
          </article>
        ))}
      </div>
    </section>
  );
}

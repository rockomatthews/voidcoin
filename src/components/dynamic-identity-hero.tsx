"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { INITIAL_BURN_REQUIREMENT, formatNumber } from "@/lib/site";

interface CurrentIdentity {
  name: string;
  symbol: string;
  image: string | null;
}

const genesis: CurrentIdentity = { name: "VOIDCOIN", symbol: "VOID", image: "/voidcoin-logo.png" };

export function DynamicIdentityHero() {
  const [identity, setIdentity] = useState(genesis);
  const [nextBurn, setNextBurn] = useState(INITIAL_BURN_REQUIREMENT);

  useEffect(() => {
    const controller = new AbortController();
    const load = () => Promise.all([
        fetch("/api/archive", { signal: controller.signal }).then((response) => response.ok ? response.json() : null),
        fetch("/api/state", { signal: controller.signal }).then((response) => response.ok ? response.json() : null),
      ]).then(([archive, state]) => {
        const current = archive?.identities?.[0] as CurrentIdentity | undefined;
        if (current) setIdentity(current);
        if (state?.nextBurnAmount) setNextBurn(state.nextBurnAmount);
      }).catch(() => undefined);
    void load();
    const interval = window.setInterval(load, 15_000);
    return () => { controller.abort(); window.clearInterval(interval); };
  }, []);

  useEffect(() => {
    document.title = `${identity.name} ($${identity.symbol}) — The coin that changes its skin`;
    const icon = document.querySelector<HTMLLinkElement>("link[rel~='icon']");
    if (icon) icon.href = identity.image ?? "/voidcoin-logo.png";
  }, [identity]);

  const image = identity.image ?? "/voidcoin-logo.png";
  const remoteImage = image.startsWith("http");

  return (
    <>
      <nav className="void-nav" aria-label="Primary navigation">
        <a className="void-mark" href="#top" aria-label={`${identity.name} home`}>
          <span><Image src={image} alt="" width={34} height={34} unoptimized={remoteImage} /></span>
          {identity.name} <small>${identity.symbol}</small>
        </a>
        <span className="network-mark">BASE MAINNET</span>
      </nav>

      <section className="void-hero" id="top" aria-labelledby="void-title">
        <div className="void-orbit"><i aria-hidden="true" /><i aria-hidden="true" /><i aria-hidden="true" /><Image src={image} alt={`${identity.name} current token image`} width={116} height={116} priority unoptimized={remoteImage} /></div>
        <p className="void-label">THE COIN THAT CHANGES ITS SKIN</p>
        <h1 id="void-title"><strong>{identity.name}</strong><span>${identity.symbol}</span></h1>
        <p className="void-message">The first identity change burns at least <b>{formatNumber(INITIAL_BURN_REQUIREMENT)} VOID</b>—0.1% of the original supply. Every challenger must beat the record by at least 250,000 VOID and may add up to 2,000,000 VOID above the live floor.</p>
        <div className="hero-burn-callout"><span>NEXT IDENTITY BURN</span><strong>{formatNumber(nextBurn)} VOID</strong></div>
        <div className="void-attributes" aria-label="Changeable token identity"><span>NAME</span><span>TICKER</span><span>PICTURE</span></div>
        <p className="void-note">The current approved name, ticker, image, and browser title all change together. The purpose of this website does not.</p>
      </section>
    </>
  );
}

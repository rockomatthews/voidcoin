"use client";

import Image from "next/image";
import { useEffect, useState, type CSSProperties } from "react";
import { BurnTerminal } from "@/components/burn-terminal";
import { BuyVoid } from "@/components/buy-void";
import { BuyVoidV2 } from "@/components/buy-void-v2";
import { configuredMarketVersion } from "@/lib/contract";
import { INITIAL_BURN_REQUIREMENT, TAKEOVER_INCREMENT, TAKEOVER_INCREASE_PERCENT, formatNumber } from "@/lib/site";
import { liveIdentityFromContract } from "@/lib/token-metadata";

interface CurrentIdentity {
  name: string;
  symbol: string;
  image: string | null;
}

const genesis: CurrentIdentity = { name: "VOIDCOIN", symbol: "VOID", image: "/voidcoin-logo.png" };
const tunnelPlanes = Array.from({ length: 12 }, (_, index) => ({
  index,
  style: {
    "--tunnel-angle": `${index * 8}deg`,
    "--tunnel-delay": `${index * -0.24}s`,
    "--tunnel-depth": `${index * -42}px`,
    "--tunnel-inset": `${index * 1.45}%`,
  } as CSSProperties,
}));

export function DynamicIdentityHero() {
  const [identity, setIdentity] = useState(genesis);
  const [nextBurn, setNextBurn] = useState(INITIAL_BURN_REQUIREMENT);

  useEffect(() => {
    const controller = new AbortController();
    const load = () => Promise.all([
        fetch("/api/archive", { signal: controller.signal }).then((response) => response.ok ? response.json() : null),
        fetch("/api/state", { signal: controller.signal }).then((response) => response.ok ? response.json() : null),
      ]).then(([archive, state]) => {
        const archived = archive?.identities?.[0] as CurrentIdentity | undefined;
        if (state?.name && state?.symbol) {
          setIdentity(liveIdentityFromContract({ name: state.name, symbol: state.symbol, image: state.image ?? null }, archived));
        }
        if (state?.nextBurnAmount) setNextBurn(state.nextBurnAmount);
      }).catch(() => undefined);
    void load();
    const interval = window.setInterval(load, 5_000);
    return () => { controller.abort(); window.clearInterval(interval); };
  }, []);

  useEffect(() => {
    document.title = `${identity.name} ($${identity.symbol}) — Try to control the coin that transforms`;
    const icon = document.querySelector<HTMLLinkElement>("link[rel~='icon']");
    if (icon) icon.href = identity.image ?? "/voidcoin-logo.png";
  }, [identity]);

  const image = identity.image ?? "/voidcoin-logo.png";
  const remoteImage = image.startsWith("http");
  const marketVersion = configuredMarketVersion();

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
        <div className="void-orbit">
          <div className="void-tunnel-planes" aria-hidden="true">
            {tunnelPlanes.map((plane) => <i key={plane.index} style={plane.style} />)}
          </div>
          <div className="void-tunnel-reticle" aria-hidden="true"><span /><span /></div>
          <div className="void-logo-core">
            <Image src={image} alt={`${identity.name} current token image`} width={164} height={164} preload unoptimized={remoteImage} />
          </div>
        </div>
        <p className="void-label">TRY TO CONTROL THE COIN THAT TRANSFORMS</p>
        <h1 id="void-title"><strong>{identity.name}</strong><span>${identity.symbol}</span></h1>
        <p className="void-message">The first identity change burns <b>{formatNumber(INITIAL_BURN_REQUIREMENT)} {identity.symbol}</b>—priced at about $1 when V2 opens. Every next record must clear both +{formatNumber(TAKEOVER_INCREMENT)} tokens and +{TAKEOVER_INCREASE_PERCENT}%. The larger increase wins.</p>
        <div className="hero-burn-callout"><span>NEXT IDENTITY BURN</span><strong>{formatNumber(nextBurn)} {identity.symbol}</strong></div>
        {marketVersion === "v2" ? <BuyVoidV2 symbol={identity.symbol} nextBurn={nextBurn} /> : <BuyVoid symbol={identity.symbol} />}
        <details className="request-drawer hero-request-drawer">
          <summary>REQUEST THE NEXT IDENTITY <span>+</span></summary>
          <BurnTerminal />
        </details>
      </section>
    </>
  );
}

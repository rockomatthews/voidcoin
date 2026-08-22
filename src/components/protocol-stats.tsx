"use client";

import { useEffect, useMemo, useState } from "react";
import { configuredMarketVersion, configuredTokenAddress, zoraTradeUrl } from "@/lib/contract";
import { INITIAL_BURN_REQUIREMENT, formatNumber, shortAddress } from "@/lib/site";
import { officialTokenLinks } from "@/lib/token-metadata";

interface ChainState {
  name: string;
  symbol: string;
  originalSupply: number;
  currentSupply: number;
  burned: number;
  recordBurn: number;
  nextBurnAmount: number;
  recordBurner: string | null;
  controllerConfigured: boolean;
  controllerReady?: boolean;
  renamePaused: boolean;
}

interface BurnEvent {
  burnId: string;
  burner: string;
  amount: number;
  transactionHash: string | null;
  timestamp: number | null;
}

interface Identity {
  burnId: string;
  name: string;
  symbol: string;
  burner: string;
  burnAmount: number;
  timestamp: number | null;
  transactionHash: string | null;
  burnTransactionHash: string | null;
}

interface MarketState {
  priceUsd: number | null;
  marketCap: number | null;
  liquidityUsd: number | null;
  volume24h: number | null;
  priceChange24h: number | null;
}

const previewState: ChainState = { name: "VOIDCOIN", symbol: "VOID", originalSupply: 1_000_000_000, currentSupply: 1_000_000_000, burned: 0, recordBurn: 0, nextBurnAmount: INITIAL_BURN_REQUIREMENT, recordBurner: null, controllerConfigured: false, renamePaused: true };
const previewMarket: MarketState = { priceUsd: null, marketCap: null, liquidityUsd: null, volume24h: null, priceChange24h: null };

function usd(value: number | null) {
  if (value === null || !Number.isFinite(value)) return "—";
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", notation: value >= 1_000_000 ? "compact" : "standard", maximumFractionDigits: value < 1 ? 4 : 0 }).format(value);
}

function when(timestamp: number | null) {
  return timestamp ? new Date(timestamp * 1000).toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short" }) : "Genesis";
}

export function ProtocolStats() {
  const contractAddress = configuredTokenAddress();
  const marketVersion = configuredMarketVersion();
  const hood = marketVersion === "hood";
  const zoraUrl = zoraTradeUrl();
  const links = contractAddress ? officialTokenLinks(contractAddress, marketVersion) : null;
  const addressUrl = (address: string) => hood
    ? `https://robinhoodchain.blockscout.com/address/${address}`
    : `https://basescan.org/address/${address}`;
  const transactionUrl = (hash: string) => hood
    ? `https://robinhoodchain.blockscout.com/tx/${hash}`
    : `https://basescan.org/tx/${hash}`;
  const [state, setState] = useState(previewState);
  const [market, setMarket] = useState(previewMarket);
  const [identities, setIdentities] = useState<Identity[]>([]);
  const [burns, setBurns] = useState<BurnEvent[]>([]);

  useEffect(() => {
    const controller = new AbortController();
    const load = () => Promise.all([
        fetch("/api/state", { signal: controller.signal }).then((response) => response.ok ? response.json() : previewState),
        fetch("/api/archive", { signal: controller.signal }).then((response) => response.ok ? response.json() : { identities: [], burns: [] }),
        fetch("/api/market", { signal: controller.signal }).then((response) => response.ok ? response.json() : previewMarket),
      ]).then(([nextState, archive, nextMarket]) => {
        setState(nextState);
        setIdentities(archive.identities ?? []);
        setBurns(archive.burns ?? []);
        setMarket(nextMarket);
      }).catch(() => undefined);
    void load();
    const interval = window.setInterval(load, 10_000);
    return () => { controller.abort(); window.clearInterval(interval); };
  }, []);

  const topBurners = useMemo(() => {
    const totals = new Map<string, { wallet: string; tokens: number; changes: number }>();
    for (const burn of burns) {
      const key = burn.burner.toLowerCase();
      const current = totals.get(key) ?? { wallet: burn.burner, tokens: 0, changes: 0 };
      current.tokens += burn.amount;
      current.changes += 1;
      totals.set(key, current);
    }
    return [...totals.values()].toSorted((a, b) => b.tokens - a.tokens).slice(0, 5);
  }, [burns]);

  const changes = identities.filter((identity) => identity.burnId !== "0");
  const burnedValue = market.priceUsd === null ? null : state.burned * market.priceUsd;

  return (
    <>
      <section className="stats-band" aria-label={`${state.name} supply statistics`}>
        <article><span>BURNED FOREVER</span><strong>{formatNumber(state.burned)}</strong><small>{((state.burned / state.originalSupply) * 100).toFixed(3)}% OF ORIGINAL SUPPLY</small></article>
        <article><span>DESTROYED VALUE</span><strong>{usd(burnedValue)}</strong><small>{market.priceUsd === null ? "WAITING FOR MARKET INDEXING" : `AT ${usd(market.priceUsd)} PER TOKEN`}</small></article>
        <article><span>CURRENT SUPPLY</span><strong>{formatNumber(state.currentSupply)}</strong><small>OUT OF {formatNumber(state.originalSupply)} MINTED</small></article>
      </section>

      <section className="market-section" aria-labelledby="market-heading">
        <div className="section-heading"><span>LIVE SIGNAL</span><h2 id="market-heading">MARKET TELEMETRY</h2></div>
        <div className="market-grid">
          <article><span>PRICE</span><strong>{usd(market.priceUsd)}</strong></article>
          <article><span>MARKET CAP</span><strong>{usd(market.marketCap)}</strong></article>
          <article><span>LIQUIDITY</span><strong>{usd(market.liquidityUsd)}</strong></article>
          <article><span>24H VOLUME</span><strong>{usd(market.volume24h)}</strong></article>
          <article><span>24H CHANGE</span><strong className={(market.priceChange24h ?? 0) >= 0 ? "positive" : "negative"}>{market.priceChange24h === null ? "—" : `${market.priceChange24h > 0 ? "+" : ""}${market.priceChange24h.toFixed(1)}%`}</strong></article>
          <article><span>IDENTITY ENGINE</span><strong>{!state.controllerConfigured || state.controllerReady === false ? "PENDING" : state.renamePaused ? "PAUSED" : "LIVE"}</strong></article>
        </div>
        <div className="market-links" aria-label="Official VOIDCOIN contract and market links">
          {contractAddress ? <>
            <div><span>CONTRACT ADDRESS</span><code>{contractAddress}</code></div>
            <nav aria-label="VOIDCOIN links">
              <a href={links?.explorer} target="_blank" rel="noreferrer">{hood ? "BLOCKSCOUT" : "BASESCAN"} ↗</a>
              {hood && links && "primaryMarket" in links ? <a href={links.primaryMarket} target="_blank" rel="noreferrer">HOOD ↗</a> : null}
              {zoraUrl ? <a href={zoraUrl} target="_blank" rel="noreferrer">ZORA ↗</a> : null}
              {!hood ? <a href={`https://app.uniswap.org/explore/tokens/base/${contractAddress}`} target="_blank" rel="noreferrer">UNISWAP ↗</a> : null}
              <a href={links?.dexScreener} target="_blank" rel="noreferrer">DEXSCREENER ↗</a>
              {!hood && links && "baseApp" in links ? <a href={links.baseApp} target="_blank" rel="noreferrer">BASE APP ↗</a> : null}
              {!hood && links && "fomo" in links ? <a href={links.fomo} target="_blank" rel="noreferrer">FOMO ↗</a> : null}
              {hood && links && "robinhoodWallet" in links ? <a href={links.robinhoodWallet} target="_blank" rel="noreferrer">ROBINHOOD WALLET ↗</a> : null}
            </nav>
          </> : <div><span>{marketVersion === "b20" ? "B20 V4" : "ZORA V3"} CONTRACT</span><code>NOT BROADCAST</code></div>}
        </div>
      </section>

      <section className="ritual-section" aria-labelledby="ritual-heading">
        <div className="section-heading"><span>THE RITUAL</span><h2 id="ritual-heading">HOW IT WORKS</h2></div>
        <div className="ritual-grid">
          <article><b>01</b><h3>Connect where it matters</h3><p>Open the identity chamber, connect your wallet, and see your {state.symbol} balance.</p></article>
          <article><b>02</b><h3>Build the next identity</h3><p>Choose the next display name, display ticker, and image. The proposal stays private during review.</p></article>
          <article><b>03</b><h3>Beat both rules</h3><p>The first record is 1,000,000 tokens. Every challenger must add at least 250,000 tokens and beat the prior record by 10%. Whichever requirement is larger controls the floor.</p></article>
          <article><b>04</b><h3>Change the visible skin</h3><p>Once approved, the token artwork, description, links, site display identity, title, and archive update together.{hood ? " The ERC-20 name and ticker remain VOIDCOIN and VOID for wallet consistency." : ""}</p></article>
        </div>
      </section>

      <section className="burners-section" aria-labelledby="burners-heading">
        <div className="section-heading"><span>HALL OF FAME</span><h2 id="burners-heading">TOP BURNERS</h2></div>
        <p className="section-intro">The wallets that have permanently destroyed the most {state.symbol} in the fight to control its identity.</p>
        <div className="burners-grid">
          {topBurners.length ? topBurners.map((burner, index) => (
            <article key={burner.wallet}><b>#{index + 1}</b><strong>{formatNumber(burner.tokens)} {state.symbol}</strong><span>{burner.changes} {burner.changes === 1 ? "burn" : "burns"}</span><a href={addressUrl(burner.wallet)} target="_blank" rel="noreferrer">{shortAddress(burner.wallet)} ↗</a></article>
          )) : <div className="stats-empty">THE FIRST BURNER WILL APPEAR HERE.</div>}
        </div>
      </section>

      <section className="changes-section" aria-labelledby="changes-heading">
        <div className="section-heading"><span>ONCHAIN LOG</span><h2 id="changes-heading">LATEST CHANGES</h2></div>
        <div className="changes-table-wrap" tabIndex={0} role="region" aria-label="Latest identity changes table">
          <table><thead><tr><th>When</th><th>Identity</th><th>Burned</th><th>By</th><th>Transactions</th></tr></thead>
            <tbody>{changes.length ? changes.slice(0, 12).map((identity) => (
              <tr key={identity.burnId}><td>{when(identity.timestamp)}</td><td><strong>{identity.name}</strong> / ${identity.symbol}</td><td>{formatNumber(identity.burnAmount)} {state.symbol}</td><td><a href={addressUrl(identity.burner)} target="_blank" rel="noreferrer">{shortAddress(identity.burner)}</a></td><td>{identity.burnTransactionHash ? <a href={transactionUrl(identity.burnTransactionHash)} target="_blank" rel="noreferrer">BURN ↗</a> : null}{identity.transactionHash ? <a href={transactionUrl(identity.transactionHash)} target="_blank" rel="noreferrer">UPDATE ↗</a> : null}</td></tr>
            )) : <tr><td colSpan={5}>NO IDENTITY CHANGES YET.</td></tr>}</tbody>
          </table>
        </div>
      </section>
    </>
  );
}

import { configuredTokenAddress, zoraTradeUrl } from "@/lib/contract";

export function TradeVoidZora({ symbol }: { symbol: string }) {
  const tokenAddress = configuredTokenAddress();
  const zoraUrl = zoraTradeUrl(tokenAddress);

  if (!tokenAddress || !zoraUrl) {
    return (
      <section className="buy-void graduated zora-trade" aria-label={`${symbol} launch status`}>
        <div><span>ZORA / BASE</span><strong>{symbol} V3 IS BEING PREPARED</strong><small>No new token has been broadcast from this branch.</small></div>
      </section>
    );
  }

  return (
    <section className="buy-void zora-trade" aria-label={`Trade ${symbol}`}>
      <div className="buy-head">
        <div><span>LIVE ON ZORA / BASE</span><strong>BUY {symbol}</strong></div>
        <span className="zora-live-dot">VISIBLE MARKET</span>
      </div>
      <p>Trade through Zora’s native market. Your purchase settles directly to your Base wallet and the token remains discoverable on Zora and Base ecosystem surfaces.</p>
      <div className="zora-trade-actions">
        <a className="buy-action" href={zoraUrl} target="_blank" rel="noreferrer">TRADE ON ZORA ↗</a>
        <a className="buy-action secondary" href={`https://base.app/coin/base-mainnet/${tokenAddress}`} target="_blank" rel="noreferrer">OPEN IN BASE APP ↗</a>
      </div>
      <small>Official contract: <code>{tokenAddress}</code></small>
    </section>
  );
}

import { configuredTokenAddress } from "@/lib/contract";

interface DexPair {
  chainId?: string;
  priceUsd?: string;
  marketCap?: number;
  fdv?: number;
  liquidity?: { usd?: number };
  volume?: { h24?: number };
  priceChange?: { h24?: number };
}

export async function GET() {
  const address = configuredTokenAddress();
  if (!address) return Response.json({ configured: false, priceUsd: null, marketCap: null, liquidityUsd: null, volume24h: null, priceChange24h: null });

  try {
    const response = await fetch(`https://api.dexscreener.com/latest/dex/tokens/${address}`, {
      next: { revalidate: 60 },
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) throw new Error("Market data unavailable");
    const payload = await response.json() as { pairs?: DexPair[] };
    const pair = (payload.pairs ?? [])
      .filter((item) => item.chainId === "base")
      .toSorted((a, b) => (b.liquidity?.usd ?? 0) - (a.liquidity?.usd ?? 0))[0];
    if (!pair) return Response.json({ configured: true, priceUsd: null, marketCap: null, liquidityUsd: null, volume24h: null, priceChange24h: null });

    return Response.json({
      configured: true,
      priceUsd: pair.priceUsd ? Number(pair.priceUsd) : null,
      marketCap: pair.marketCap ?? pair.fdv ?? null,
      liquidityUsd: pair.liquidity?.usd ?? null,
      volume24h: pair.volume?.h24 ?? null,
      priceChange24h: pair.priceChange?.h24 ?? null,
    }, { headers: { "Cache-Control": "public, s-maxage=60, stale-while-revalidate=180" } });
  } catch {
    return Response.json({ configured: true, priceUsd: null, marketCap: null, liquidityUsd: null, volume24h: null, priceChange24h: null });
  }
}

export interface TokenMetadata {
  name?: string;
  symbol?: string;
  image?: string;
}

export interface DisplayIdentity {
  name: string;
  symbol: string;
  image: string | null;
}

export function liveIdentityFromContract(state: DisplayIdentity, archived?: DisplayIdentity): DisplayIdentity {
  const archiveMatches = archived?.name === state.name && archived?.symbol === state.symbol;
  return { ...state, image: state.image ?? (archiveMatches ? archived?.image ?? null : null) };
}

export function ipfsGatewayUrl(uri: string) {
  if (!uri.startsWith("ipfs://")) return null;
  const cid = uri.slice(7).replace(/^ipfs\//, "");
  if (!cid) return null;
  const gateway = (process.env.PINATA_GATEWAY ?? "https://gateway.pinata.cloud/ipfs").replace(/\/$/, "");
  return `${gateway}/${cid}`;
}

export async function imageFromTokenURI(uri: string) {
  const url = ipfsGatewayUrl(uri);
  if (!url) return null;
  try {
    const response = await fetch(url, { next: { revalidate: 30 }, signal: AbortSignal.timeout(5_000) });
    if (!response.ok) return null;
    const metadata = await response.json() as TokenMetadata;
    return typeof metadata.image === "string" ? ipfsGatewayUrl(metadata.image) : null;
  } catch {
    return null;
  }
}

export function approvedTokenMetadata(name: string, symbol: string, imageURI: string) {
  return {
    interop: { type: "erc20", version: "1.0.0" },
    name,
    symbol,
    image: imageURI,
    description: "An approved VOIDCOIN identity.",
  } as const;
}

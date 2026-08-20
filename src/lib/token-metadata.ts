export interface TokenMetadata {
  name?: string;
  symbol?: string;
  image?: string;
}

export const OFFICIAL_WEBSITE = "https://voidcoin.fun";

export function officialTokenLinks(contractAddress: `0x${string}`) {
  return {
    website: OFFICIAL_WEBSITE,
    baseApp: `https://base.app/coin/base-mainnet/${contractAddress}`,
    fomo: `https://fomo.family/tokens/base/${contractAddress}`,
    dexScreener: `https://dexscreener.com/base/${contractAddress}`,
    explorer: `https://basescan.org/token/${contractAddress}`,
  } as const;
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
    const response = await fetch(url, { next: { revalidate: 30 }, signal: AbortSignal.timeout(12_000) });
    if (!response.ok) return null;
    const metadata = await response.json() as TokenMetadata;
    return typeof metadata.image === "string" ? ipfsGatewayUrl(metadata.image) : null;
  } catch {
    return null;
  }
}

export const imageFromContractURI = imageFromTokenURI;

export function approvedTokenMetadata(
  name: string,
  symbol: string,
  imageURI: string,
  contractAddress: `0x${string}`,
) {
  const links = officialTokenLinks(contractAddress);
  return {
    interop: { erc1046: true, erc7572: true },
    name,
    symbol,
    standard: "B20",
    launchpad: "VOIDCOIN",
    launchpadUrl: OFFICIAL_WEBSITE,
    decimals: 18,
    image: imageURI,
    images: [imageURI],
    icons: [imageURI],
    description: `${name} ($${symbol}) is the current approved identity of the Base-native VOIDCOIN competitive-burn protocol. The token's name, ticker, and image can change after a new record burn and moderation approval; ${OFFICIAL_WEBSITE} remains permanent.`,
    external_url: OFFICIAL_WEBSITE,
    website: OFFICIAL_WEBSITE,
    chain_id: 8453,
    contract_address: contractAddress,
    links: { website: links.website },
    properties: {
      network: "Base Mainnet",
      chainId: 8453,
      contractAddress,
      ...links,
    },
  } as const;
}

export interface TokenMetadata {
  name?: string;
  symbol?: string;
  image?: string;
}

export const OFFICIAL_WEBSITE = "https://voidcoin.fun";

export function officialBaseTokenLinks(contractAddress: `0x${string}`) {
  return {
    website: OFFICIAL_WEBSITE,
    baseApp: `https://base.app/coin/base-mainnet/${contractAddress}`,
    fomo: `https://fomo.family/tokens/base/${contractAddress}`,
    dexScreener: `https://dexscreener.com/base/${contractAddress}`,
    explorer: `https://basescan.org/token/${contractAddress}`,
  } as const;
}

export function officialHoodTokenLinks(contractAddress: `0x${string}`) {
  return {
    website: OFFICIAL_WEBSITE,
    fomo: `https://fomo.family/tokens/robinhood/${contractAddress}`,
    hoodTerminal: "https://hood.dev",
    walletHelp: "https://robinhood.com/us/en/support/articles/robinhood-wallet/",
    dexScreener: `https://dexscreener.com/robinhood/${contractAddress}`,
    explorer: `https://robinhoodchain.blockscout.com/token/${contractAddress}`,
  } as const;
}

export function officialTokenLinks(contractAddress: `0x${string}`, marketVersion: "hood" | "b20" | "unconfigured" = "b20") {
  return marketVersion === "hood" ? officialHoodTokenLinks(contractAddress) : officialBaseTokenLinks(contractAddress);
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

export function tokenContentUrl(uri: string) {
  if (uri.startsWith("https://")) return uri;
  if (uri.startsWith("ar://")) return `https://arweave.net/${uri.slice(5)}`;
  return ipfsGatewayUrl(uri);
}

export async function imageFromTokenURI(uri: string) {
  const url = tokenContentUrl(uri);
  if (!url) return null;
  try {
    const response = await fetch(url, { next: { revalidate: 30 }, signal: AbortSignal.timeout(12_000) });
    if (!response.ok) return null;
    const metadata = await response.json() as TokenMetadata;
    return typeof metadata.image === "string" ? tokenContentUrl(metadata.image) : null;
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
  const links = officialBaseTokenLinks(contractAddress);
  const uniswap = `https://app.uniswap.org/explore/tokens/base/${contractAddress}`;
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
    // Basecat/PAMPU exposes links.website. Keep the richer typed routes as well.
    // Captured source: docs/research/basecat-b20-metadata.json.
    links: { ...links, uniswap },
    market_links: [
      { type: "website", label: "Website", url: links.website },
      { type: "base", label: "Base App", url: links.baseApp },
      { type: "fomo", label: "Fomo", url: links.fomo },
      { type: "uniswap", label: "Uniswap", url: uniswap },
      { type: "dexscreener", label: "DEX Screener", url: links.dexScreener },
      { type: "explorer", label: "Contract", url: links.explorer },
    ],
    properties: {
      network: "Base Mainnet",
      chainId: 8453,
      contractAddress,
      standard: "B20",
      uniswap,
      ...links,
    },
  } as const;
}

export function approvedHoodTokenMetadata(
  name: string,
  symbol: string,
  imageURI: string,
  contractAddress: `0x${string}`,
) {
  const links = officialHoodTokenLinks(contractAddress);
  return {
    name,
    symbol,
    image: imageURI,
    description: `${name} ($${symbol}) is the current community-controlled display identity of VOIDCOIN on Robinhood Chain. Record holders can change the artwork, description, links, and website identity after an approved permanent burn. The immutable ERC-20 identity remains VOIDCOIN (VOID).`,
    decimals: 18,
    external_url: OFFICIAL_WEBSITE,
    website: OFFICIAL_WEBSITE,
    chain_id: 4663,
    contract_address: contractAddress,
    links,
    market_links: [
      { type: "website", label: "Website", url: links.website },
      { type: "fomo", label: "Buy on Fomo", url: links.fomo },
      { type: "terminal", label: "hood.dev", url: links.hoodTerminal },
      { type: "dexscreener", label: "DEX Screener", url: links.dexScreener },
      { type: "explorer", label: "Contract", url: links.explorer },
      { type: "wallet-help", label: "Robinhood Wallet help", url: links.walletHelp },
    ],
    properties: {
      network: "Robinhood Chain",
      chainId: 4663,
      contractAddress,
      launchpad: "hood.dev",
      immutableErc20Name: "VOIDCOIN",
      immutableErc20Symbol: "VOID",
      displayName: name,
      displaySymbol: symbol,
    },
  } as const;
}

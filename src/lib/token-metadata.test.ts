import { afterEach, describe, expect, it } from "vitest";
import { approvedHoodTokenMetadata, approvedTokenMetadata, ipfsGatewayUrl, liveIdentityFromContract, officialTokenLinks } from "./token-metadata";

const originalGateway = process.env.PINATA_GATEWAY;

afterEach(() => {
  process.env.PINATA_GATEWAY = originalGateway;
});

describe("token identity metadata", () => {
  it("publishes the approved name, ticker, and image together", () => {
    const address = "0x1111111111111111111111111111111111111111";
    const metadata = approvedTokenMetadata("Night Shift", "NIGHT", "ipfs://image-cid", address);
    expect(metadata).toMatchObject({
      interop: { erc1046: true, erc7572: true },
      name: "Night Shift",
      symbol: "NIGHT",
      standard: "B20",
      launchpad: "VOIDCOIN",
      launchpadUrl: "https://voidcoin.fun",
      decimals: 18,
      image: "ipfs://image-cid",
      images: ["ipfs://image-cid"],
      icons: ["ipfs://image-cid"],
      external_url: "https://voidcoin.fun",
      website: "https://voidcoin.fun",
      chain_id: 8453,
      contract_address: address,
    });
    expect(metadata.description).toContain("https://voidcoin.fun remains permanent");
    expect(metadata.properties.dexScreener).toBe(`https://dexscreener.com/base/${address}`);
    expect(metadata.links.website).toBe("https://voidcoin.fun");
    expect(metadata.market_links).toHaveLength(6);
    expect(metadata.market_links).toContainEqual({ type: "fomo", label: "Fomo", url: `https://fomo.family/tokens/base/${address}` });
  });

  it("builds Base App and Fomo token routes from the immutable contract address", () => {
    const address = "0x1111111111111111111111111111111111111111";
    expect(officialTokenLinks(address)).toEqual({
      website: "https://voidcoin.fun",
      baseApp: `https://base.app/coin/base-mainnet/${address}`,
      fomo: `https://fomo.family/tokens/base/${address}`,
      dexScreener: `https://dexscreener.com/base/${address}`,
      explorer: `https://basescan.org/token/${address}`,
    });
  });

  it("publishes Robinhood Chain launchpad and wallet discovery routes without claiming a brokerage listing", () => {
    const address = "0x1111111111111111111111111111111111111111";
    const metadata = approvedHoodTokenMetadata("Night Shift", "NIGHT", "ipfs://image-cid", address);
    expect(metadata).toMatchObject({ chain_id: 4663, contract_address: address });
    expect(metadata.description).toContain("immutable ERC-20 identity remains VOIDCOIN (VOID)");
    expect(officialTokenLinks(address, "hood")).toEqual({
      website: "https://voidcoin.fun",
      fomo: `https://fomo.family/tokens/robinhood/${address}`,
      hoodTerminal: "https://hood.dev",
      walletHelp: "https://robinhood.com/us/en/support/articles/robinhood-wallet/",
      dexScreener: `https://dexscreener.com/robinhood/${address}`,
      explorer: `https://robinhoodchain.blockscout.com/token/${address}`,
    });
    expect(metadata.market_links).toContainEqual({ type: "fomo", label: "Buy on Fomo", url: `https://fomo.family/tokens/robinhood/${address}` });
  });

  it("resolves IPFS metadata and images through the configured gateway", () => {
    process.env.PINATA_GATEWAY = "https://voidcoin.mypinata.cloud/ipfs/";
    expect(ipfsGatewayUrl("ipfs://metadata-cid")).toBe("https://voidcoin.mypinata.cloud/ipfs/metadata-cid");
    expect(ipfsGatewayUrl("https://example.com/not-ipfs")).toBeNull();
  });

  it("keeps the contract identity authoritative when the archive is stale", () => {
    expect(liveIdentityFromContract(
      { name: "Night Shift", symbol: "NIGHT", image: "https://gateway/ipfs/new" },
      { name: "VOIDCOIN", symbol: "VOID", image: "/voidcoin-logo.png" },
    )).toEqual({ name: "Night Shift", symbol: "NIGHT", image: "https://gateway/ipfs/new" });
  });

  it("uses the matching archive image only during a temporary IPFS read failure", () => {
    expect(liveIdentityFromContract(
      { name: "Night Shift", symbol: "NIGHT", image: null },
      { name: "Night Shift", symbol: "NIGHT", image: "https://gateway/ipfs/night" },
    ).image).toBe("https://gateway/ipfs/night");
  });
});

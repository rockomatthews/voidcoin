import { afterEach, describe, expect, it } from "vitest";
import { approvedTokenMetadata, ipfsGatewayUrl, liveIdentityFromContract } from "./token-metadata";

const originalGateway = process.env.PINATA_GATEWAY;

afterEach(() => {
  process.env.PINATA_GATEWAY = originalGateway;
});

describe("token identity metadata", () => {
  it("publishes the approved name, ticker, and image together", () => {
    expect(approvedTokenMetadata("Night Shift", "NIGHT", "ipfs://image-cid")).toEqual({
      interop: { type: "erc20", version: "1.0.0" },
      name: "Night Shift",
      symbol: "NIGHT",
      image: "ipfs://image-cid",
      description: "An approved VOIDCOIN identity.",
    });
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

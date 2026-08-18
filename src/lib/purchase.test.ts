import { describe, expect, it } from "vitest";
import { minimumTokensOut, uniswapBuyUrl } from "./purchase";

describe("VOID purchase safety", () => {
  it("keeps a one-percent execution buffer under the displayed quote", () => {
    expect(minimumTokensOut(1_000_000n)).toBe(990_000n);
  });

  it("sends graduated trading to Base Uniswap for the immutable token", () => {
    expect(uniswapBuyUrl()).toBe("https://app.uniswap.org/swap?chain=base&outputCurrency=0xF6508F41851E1E956113b31571E67A315D0832A4");
  });
});

import { describe, expect, it } from "vitest";
import { CANONICAL_SITE_URL, getSiteUrl, nextTakeoverRequirement } from "./site";

describe("getSiteUrl", () => {
  it("keeps the permanent VOIDCOIN website canonical in every environment", () => {
    expect(getSiteUrl()).toBe("https://voidcoin.fun");
    expect(CANONICAL_SITE_URL).toBe("https://voidcoin.fun");
  });
});

describe("nextTakeoverRequirement", () => {
  it("uses the larger of the 250K minimum step and 10% increase", () => {
    expect(nextTakeoverRequirement(0)).toBe(1_000_000);
    expect(nextTakeoverRequirement(1_000_000)).toBe(1_250_000);
    expect(nextTakeoverRequirement(3_000_000)).toBe(3_300_000);
  });
});

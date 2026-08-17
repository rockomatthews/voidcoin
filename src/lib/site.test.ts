import { describe, expect, it } from "vitest";
import { CANONICAL_SITE_URL, getSiteUrl } from "./site";

describe("getSiteUrl", () => {
  it("keeps the permanent VOIDCOIN website canonical in every environment", () => {
    expect(getSiteUrl()).toBe("https://voidcoin.fun");
    expect(CANONICAL_SITE_URL).toBe("https://voidcoin.fun");
  });
});

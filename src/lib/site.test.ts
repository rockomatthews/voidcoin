import { afterEach, describe, expect, it } from "vitest";
import { getSiteUrl } from "./site";

const originalSiteUrl = process.env.NEXT_PUBLIC_SITE_URL;
const originalProductionUrl = process.env.VERCEL_PROJECT_PRODUCTION_URL;
const originalVercelUrl = process.env.VERCEL_URL;

afterEach(() => {
  process.env.NEXT_PUBLIC_SITE_URL = originalSiteUrl;
  process.env.VERCEL_PROJECT_PRODUCTION_URL = originalProductionUrl;
  process.env.VERCEL_URL = originalVercelUrl;
});

describe("getSiteUrl", () => {
  it("falls back when NEXT_PUBLIC_SITE_URL is blank", () => {
    process.env.NEXT_PUBLIC_SITE_URL = "";
    process.env.VERCEL_PROJECT_PRODUCTION_URL = "voidcoin.vercel.app";
    expect(getSiteUrl()).toBe("https://voidcoin.vercel.app");
  });

  it("normalizes a configured URL", () => {
    process.env.NEXT_PUBLIC_SITE_URL = " https://voidcoin.example/ ";
    expect(getSiteUrl()).toBe("https://voidcoin.example");
  });

  it("uses localhost when no deployment URL exists", () => {
    delete process.env.NEXT_PUBLIC_SITE_URL;
    delete process.env.VERCEL_PROJECT_PRODUCTION_URL;
    delete process.env.VERCEL_URL;
    expect(getSiteUrl()).toBe("http://localhost:3000");
  });
});

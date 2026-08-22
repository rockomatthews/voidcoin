import { afterEach, describe, expect, it } from "vitest";
import {
  configuredControllerAddress,
  configuredChainId,
  configuredMarketVersion,
  configuredMetadataFunction,
  configuredTokenAddress,
  zoraTradeUrl,
} from "./contract";

const originalB20 = process.env.NEXT_PUBLIC_VOID_B20_ADDRESS;
const originalB20Controller = process.env.NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS;
const originalZora = process.env.NEXT_PUBLIC_ZORA_VOID_ADDRESS;
const originalHood = process.env.NEXT_PUBLIC_VOID_HOOD_TOKEN;
const originalHoodController = process.env.NEXT_PUBLIC_VOID_HOOD_CONTROLLER;

afterEach(() => {
  restore("NEXT_PUBLIC_VOID_B20_ADDRESS", originalB20);
  restore("NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS", originalB20Controller);
  restore("NEXT_PUBLIC_ZORA_VOID_ADDRESS", originalZora);
  restore("NEXT_PUBLIC_VOID_HOOD_TOKEN", originalHood);
  restore("NEXT_PUBLIC_VOID_HOOD_CONTROLLER", originalHoodController);
});

function restore(key: string, value: string | undefined) {
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

describe("production token adapter", () => {
  it("selects Robinhood Chain and the Hood controller for V5", () => {
    process.env.NEXT_PUBLIC_VOID_HOOD_TOKEN = "0x3333333333333333333333333333333333333333";
    process.env.NEXT_PUBLIC_VOID_HOOD_CONTROLLER = "0x4444444444444444444444444444444444444444";
    expect(configuredMarketVersion()).toBe("hood");
    expect(configuredChainId()).toBe(4663);
    expect(configuredTokenAddress()).toBe("0x3333333333333333333333333333333333333333");
    expect(configuredControllerAddress()).toBe("0x4444444444444444444444444444444444444444");
  });

  it("selects B20 contractURI and controller when V4 is configured", () => {
    process.env.NEXT_PUBLIC_VOID_B20_ADDRESS = "0x1111111111111111111111111111111111111111";
    process.env.NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS = "0x2222222222222222222222222222222222222222";
    expect(configuredMarketVersion()).toBe("b20");
    expect(configuredMetadataFunction()).toBe("contractURI");
    expect(configuredTokenAddress()).toBe("0x1111111111111111111111111111111111111111");
    expect(configuredControllerAddress()).toBe("0x2222222222222222222222222222222222222222");
    expect(zoraTradeUrl()).toBeNull();
  });

  it("fails closed instead of falling back to the obsolete Zora token", () => {
    delete process.env.NEXT_PUBLIC_VOID_B20_ADDRESS;
    process.env.NEXT_PUBLIC_ZORA_VOID_ADDRESS = "0x4A64F213558Fb0188e3FC48918948EC590A66733";
    expect(configuredMarketVersion()).toBe("unconfigured");
    expect(configuredMetadataFunction()).toBe("contractURI");
    expect(configuredTokenAddress()).toBeNull();
    expect(zoraTradeUrl()).toBeNull();
  });

  it("rejects malformed B20 and controller addresses", () => {
    process.env.NEXT_PUBLIC_VOID_B20_ADDRESS = "0xnot-an-address00000000000000000000000000";
    process.env.NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS = "0x222222222222222222222222222222222222222z";
    expect(configuredTokenAddress()).toBeNull();
    expect(configuredControllerAddress()).toBeNull();
  });
});

import { afterEach, describe, expect, it } from "vitest";
import {
  configuredControllerAddress,
  configuredMarketVersion,
  configuredMetadataFunction,
  configuredTokenAddress,
  zoraTradeUrl,
} from "./contract";

const originalB20 = process.env.NEXT_PUBLIC_VOID_B20_ADDRESS;
const originalB20Controller = process.env.NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS;
const originalZora = process.env.NEXT_PUBLIC_ZORA_VOID_ADDRESS;

afterEach(() => {
  restore("NEXT_PUBLIC_VOID_B20_ADDRESS", originalB20);
  restore("NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS", originalB20Controller);
  restore("NEXT_PUBLIC_ZORA_VOID_ADDRESS", originalZora);
});

function restore(key: string, value: string | undefined) {
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

describe("production token adapter", () => {
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

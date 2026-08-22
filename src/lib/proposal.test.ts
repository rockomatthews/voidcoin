import { describe, expect, it } from "vitest";
import { createCommitment, createHoodCommitment, parseStrategicBurn, proposalSchema } from "./proposal";

const wallet = "0x0000000000000000000000000000000000000001" as const;
const contract = "0x0000000000000000000000000000000000000002" as const;
const hash = `0x${"11".repeat(32)}` as const;
const salt = `0x${"22".repeat(32)}` as const;

describe("proposal validation", () => {
  it("accepts the onchain character rules", () => {
    expect(proposalSchema.parse({ wallet, name: "Night Shift", symbol: "NIGHT" }).name).toBe("Night Shift");
  });

  it.each([" leading", "trailing ", "two  spaces", "bad-name", ""])("rejects invalid name %j", (name) => {
    expect(proposalSchema.safeParse({ wallet, name, symbol: "VOID" }).success).toBe(false);
  });

  it("creates a stable typed commitment", () => {
    const input = { chainId: 8453, contractAddress: contract, burnId: 1n, burner: wallet, burnAmount: 1_000_000n * 10n ** 18n, name: "VOIDCOIN", symbol: "VOID", imageHash: hash, metadataURIHash: hash, salt };
    expect(createCommitment(input)).toBe(createCommitment(input));
    expect(createCommitment(input)).not.toBe(createCommitment({ ...input, metadataURIHash: salt }));
  });

  it("binds every V5 Hood skin field to the controller and Robinhood Chain", () => {
    const input = {
      chainId: 4663,
      controllerAddress: contract,
      burnId: 1n,
      burner: wallet,
      burnAmount: 1_000_000n * 10n ** 18n,
      name: "NEON VOID",
      symbol: "NEON",
      image: "ipfs://image",
      description: "approved description",
      socials: '{"website":"https://voidcoin.fun"}',
      metadataURI: "ipfs://metadata",
      salt,
    } as const;
    expect(createHoodCommitment(input)).toBe(createHoodCommitment(input));
    expect(createHoodCommitment(input)).not.toBe(createHoodCommitment({ ...input, image: "ipfs://different" }));
    expect(createHoodCommitment(input)).not.toBe(createHoodCommitment({ ...input, chainId: 8453 }));
  });
});

describe("strategic burn validation", () => {
  const minimum = 1_250_000n * 10n ** 18n;

  it("accepts the live minimum and a higher strategic record", () => {
    const maximum = 3_250_000n * 10n ** 18n;
    expect(parseStrategicBurn("1250000", minimum, maximum)).toBe(minimum);
    expect(parseStrategicBurn("2000000", minimum, maximum)).toBe(2_000_000n * 10n ** 18n);
  });

  it("rejects stale, fractional, malformed, and impossible amounts", () => {
    const maximum = 3_250_000n * 10n ** 18n;
    expect(() => parseStrategicBurn("1000000", minimum, maximum)).toThrow("at least 1250000");
    expect(() => parseStrategicBurn("1250000.5", minimum, maximum)).toThrow("whole number");
    expect(() => parseStrategicBurn("2e6", minimum, maximum)).toThrow("whole number");
    expect(() => parseStrategicBurn("3250001", minimum, maximum)).toThrow("cannot exceed 3250000");
  });
});

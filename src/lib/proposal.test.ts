import { describe, expect, it } from "vitest";
import { createCommitment, proposalSchema } from "./proposal";

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
    const input = { chainId: 84532, contractAddress: contract, burnId: 1n, burner: wallet, name: "VOIDCOIN", symbol: "VOID", imageHash: hash, salt };
    expect(createCommitment(input)).toBe(createCommitment(input));
  });
});

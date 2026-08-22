import {
  encodeAbiParameters,
  isAddress,
  keccak256,
  parseUnits,
  parseAbiParameters,
  type Address,
  type Hex,
} from "viem";
import { z } from "zod";

export const proposalSchema = z.object({
  wallet: z.string().refine(isAddress, "Invalid wallet address"),
  name: z
    .string()
    .min(1)
    .max(15)
    .regex(/^[A-Za-z0-9]+(?: [A-Za-z0-9]+)*$/, "Use letters, numbers, and single spaces only"),
  symbol: z.string().min(1).max(10).regex(/^[A-Za-z0-9]+$/, "Use letters and numbers only"),
  email: z.string().email().optional().or(z.literal("")),
});

export interface CommitmentInput {
  chainId: number;
  contractAddress: Address;
  burnId: bigint;
  burner: Address;
  burnAmount: bigint;
  name: string;
  symbol: string;
  imageHash: Hex;
  metadataURIHash: Hex;
  salt: Hex;
}

export interface HoodCommitmentInput {
  chainId: number;
  controllerAddress: Address;
  burnId: bigint;
  burner: Address;
  burnAmount: bigint;
  name: string;
  symbol: string;
  image: string;
  description: string;
  socials: string;
  metadataURI: string;
  salt: Hex;
}

export function parseStrategicBurn(input: string, minimum: bigint, maximum: bigint): bigint {
  if (!/^\d+$/.test(input)) throw new Error("Burn amount must be a whole number of VOID");
  const amount = parseUnits(input, 18);
  if (amount < minimum) throw new Error(`Burn amount must be at least ${minimum / 10n ** 18n} VOID`);
  if (amount > maximum) throw new Error(`Burn amount cannot exceed ${maximum / 10n ** 18n} VOID for this record`);
  return amount;
}

export function createCommitment(input: CommitmentInput): Hex {
  return keccak256(
    encodeAbiParameters(
      parseAbiParameters("uint256 chainId, address token, uint256 burnId, address burner, uint256 burnAmount, string name, string symbol, bytes32 imageHash, bytes32 metadataURIHash, bytes32 salt"),
      [
        BigInt(input.chainId),
        input.contractAddress,
        input.burnId,
        input.burner,
        input.burnAmount,
        input.name,
        input.symbol,
        input.imageHash,
        input.metadataURIHash,
        input.salt,
      ],
    ),
  );
}

export function createHoodCommitment(input: HoodCommitmentInput): Hex {
  const skinHash = keccak256(
    encodeAbiParameters(
      parseAbiParameters("string name, string symbol, bytes32 imageHash, bytes32 descriptionHash, bytes32 socialsHash, bytes32 metadataURIHash"),
      [
        input.name,
        input.symbol,
        keccak256(new TextEncoder().encode(input.image)),
        keccak256(new TextEncoder().encode(input.description)),
        keccak256(new TextEncoder().encode(input.socials)),
        keccak256(new TextEncoder().encode(input.metadataURI)),
      ],
    ),
  );
  return keccak256(
    encodeAbiParameters(
      parseAbiParameters("uint256 chainId, address controller, uint256 burnId, address burner, uint256 burnAmount, bytes32 skinHash, bytes32 salt"),
      [
        BigInt(input.chainId),
        input.controllerAddress,
        input.burnId,
        input.burner,
        input.burnAmount,
        skinHash,
        input.salt,
      ],
    ),
  );
}

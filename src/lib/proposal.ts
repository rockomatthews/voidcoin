import {
  encodeAbiParameters,
  isAddress,
  keccak256,
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

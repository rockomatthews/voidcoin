import { base } from "viem/chains";

export const MAINNET_VOIDCOIN_ADDRESS = "0xF6508F41851E1E956113b31571E67A315D0832A4" as const;
export const MAINNET_VOID_CURVE_ADDRESS = "0x5963228022a745f1F0DE3ce82001774968982924" as const;

export const voidCoinAbi = [
  {
    type: "function",
    name: "burnForRename",
    stateMutability: "nonpayable",
    inputs: [
      { name: "burnAmount", type: "uint256" },
      { name: "commitment", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "replaceCommitment",
    stateMutability: "nonpayable",
    inputs: [{ name: "newCommitment", type: "bytes32" }],
    outputs: [],
  },
  {
    type: "function",
    name: "approveRename",
    stateMutability: "nonpayable",
    inputs: [
      { name: "burnId", type: "uint256" },
      { name: "proposedName", type: "string" },
      { name: "proposedSymbol", type: "string" },
      { name: "metadataURI", type: "string" },
      { name: "imageHash", type: "bytes32" },
      { name: "salt", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "lockRenameSlot",
    stateMutability: "nonpayable",
    inputs: [{ name: "burnId", type: "uint256" }],
    outputs: [],
  },
  { type: "function", name: "currentBurnId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nextBurnId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "recordBurn", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "recordBurner", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "nextBurnRequirement", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "maximumBurnAmount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "destroyedSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "tokenURI", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "renamePaused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  {
    type: "function",
    name: "activeSlot",
    stateMutability: "view",
    inputs: [],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "burnId", type: "uint256" },
          { name: "burner", type: "address" },
          { name: "burnAmount", type: "uint256" },
          { name: "commitment", type: "bytes32" },
          { name: "openedAt", type: "uint64" },
          { name: "lockedUntil", type: "uint64" },
        ],
      },
    ],
  },
  {
    type: "event",
    name: "RenameBurned",
    inputs: [
      { name: "burnId", type: "uint256", indexed: true },
      { name: "burner", type: "address", indexed: true },
      { name: "commitment", type: "bytes32", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "previousRecord", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "CommitmentReplaced",
    inputs: [
      { name: "burnId", type: "uint256", indexed: true },
      { name: "burner", type: "address", indexed: true },
      { name: "commitment", type: "bytes32", indexed: true },
    ],
  },
  {
    type: "event",
    name: "SkinChanged",
    inputs: [
      { name: "burnId", type: "uint256", indexed: true },
      { name: "burner", type: "address", indexed: true },
      { name: "name", type: "string", indexed: false },
      { name: "symbol", type: "string", indexed: false },
      { name: "metadataURI", type: "string", indexed: false },
      { name: "imageHash", type: "bytes32", indexed: false },
    ],
  },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

export const voidBondingCurveAbi = [
  { type: "function", name: "buy", stateMutability: "payable", inputs: [{ name: "minimumTokensOut", type: "uint256" }, { name: "deadline", type: "uint256" }], outputs: [{ name: "tokensOut", type: "uint256" }] },
  { type: "function", name: "quoteBuy", stateMutability: "view", inputs: [{ name: "ethIn", type: "uint256" }], outputs: [{ name: "tokensOut", type: "uint256" }] },
  { type: "function", name: "maxBuyAmount", stateMutability: "view", inputs: [], outputs: [{ name: "amount", type: "uint256" }] },
  { type: "function", name: "ethReserve", stateMutability: "view", inputs: [], outputs: [{ name: "amount", type: "uint256" }] },
  { type: "function", name: "graduationThreshold", stateMutability: "view", inputs: [], outputs: [{ name: "amount", type: "uint256" }] },
  { type: "function", name: "graduated", stateMutability: "view", inputs: [], outputs: [{ name: "value", type: "bool" }] },
] as const;

export function configuredChainId() {
  return base.id;
}

export function configuredChain() {
  return base;
}

export function configuredContractAddress() {
  const address = process.env.NEXT_PUBLIC_VOIDCOIN_ADDRESS;
  return address?.startsWith("0x") && address.length === 42 ? (address as `0x${string}`) : MAINNET_VOIDCOIN_ADDRESS;
}

export function configuredCurveAddress() {
  const address = process.env.NEXT_PUBLIC_BONDING_CURVE_ADDRESS ?? process.env.NEXT_PUBLIC_VOID_CURVE_ADDRESS;
  return address?.startsWith("0x") && address.length === 42 ? (address as `0x${string}`) : MAINNET_VOID_CURVE_ADDRESS;
}

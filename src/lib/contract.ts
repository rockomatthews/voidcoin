import { defineChain, getAddress, isAddress } from "viem";
import { base } from "viem/chains";

export const robinhoodChain = defineChain({
  id: 4663,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://rpc.mainnet.chain.robinhood.com"] } },
  blockExplorers: { default: { name: "Blockscout", url: "https://robinhoodchain.blockscout.com" } },
});

export const MAINNET_VOIDCOIN_ADDRESS = "0xF6508F41851E1E956113b31571E67A315D0832A4" as const;
export const MAINNET_ZORA_VOID_ADDRESS = "0x4A64F213558Fb0188e3FC48918948EC590A66733" as const;
export const MAINNET_VOID_CURVE_ADDRESS = "0x5963228022a745f1F0DE3ce82001774968982924" as const;
export const BASE_WETH_ADDRESS = "0x4200000000000000000000000000000000000006" as const;
export const BASE_USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" as const;
export const BASE_UNISWAP_V3_QUOTER_V2 = "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a" as const;
export const WETH_USDC_POOL_FEE = 500;
export const VOID_USDC_POOL_FEE = 10_000;

export const voidSkinControllerAbi = [
  { type: "function", name: "token", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  {
    type: "function",
    name: "burnForRename",
    stateMutability: "nonpayable",
    inputs: [
      { name: "expectedBurnId", type: "uint256" },
      { name: "burnAmount", type: "uint256" },
      { name: "commitment", type: "bytes32" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "replaceCommitment",
    stateMutability: "nonpayable",
    inputs: [
      { name: "expectedBurnId", type: "uint256" },
      { name: "newCommitment", type: "bytes32" },
    ],
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
  { type: "function", name: "destroyedSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "contestBurned", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "renamePaused", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "controllerReady", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
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
] as const;

export const voidTokenAbi = [
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "tokenURI", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "contractURI", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "image", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "account", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ name: "owner", type: "address" }, { name: "spender", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

export const hoodSkinControllerAbi = [
  ...voidSkinControllerAbi.filter((item) => item.type !== "function" || item.name !== "approveRename"),
  { type: "function", name: "displayName", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "displaySymbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  {
    type: "function",
    name: "skinHash",
    stateMutability: "pure",
    inputs: [{
      name: "proposal",
      type: "tuple",
      components: [
        { name: "displayName", type: "string" },
        { name: "displaySymbol", type: "string" },
        { name: "image", type: "string" },
        { name: "description", type: "string" },
        { name: "socials", type: "string" },
        { name: "metadataURI", type: "string" },
      ],
    }],
    outputs: [{ type: "bytes32" }],
  },
  {
    type: "function",
    name: "approveRename",
    stateMutability: "nonpayable",
    inputs: [
      { name: "burnId", type: "uint256" },
      {
        name: "proposal",
        type: "tuple",
        components: [
          { name: "displayName", type: "string" },
          { name: "displaySymbol", type: "string" },
          { name: "image", type: "string" },
          { name: "description", type: "string" },
          { name: "socials", type: "string" },
          { name: "metadataURI", type: "string" },
        ],
      },
      { name: "salt", type: "bytes32" },
    ],
    outputs: [],
  },
] as const;

export const zoraContentCoinAbi = voidTokenAbi;

// Historical V1/V2 modules still import this name. Production identity code uses
// voidSkinControllerAbi plus voidTokenAbi so V3 tokenURI and V4 contractURI coexist.
export const voidCoinAbi = voidSkinControllerAbi;

export const voidBondingCurveAbi = [
  { type: "function", name: "buy", stateMutability: "payable", inputs: [{ name: "minimumTokensOut", type: "uint256" }, { name: "deadline", type: "uint256" }], outputs: [{ name: "tokensOut", type: "uint256" }] },
  { type: "function", name: "quoteBuy", stateMutability: "view", inputs: [{ name: "ethIn", type: "uint256" }], outputs: [{ name: "tokensOut", type: "uint256" }] },
  { type: "function", name: "maxBuyAmount", stateMutability: "view", inputs: [], outputs: [{ name: "amount", type: "uint256" }] },
  { type: "function", name: "ethReserve", stateMutability: "view", inputs: [], outputs: [{ name: "amount", type: "uint256" }] },
  { type: "function", name: "graduationThreshold", stateMutability: "view", inputs: [], outputs: [{ name: "amount", type: "uint256" }] },
  { type: "function", name: "graduated", stateMutability: "view", inputs: [], outputs: [{ name: "value", type: "bool" }] },
] as const;

export const voidV2BuyRouterAbi = [
  {
    type: "function",
    name: "buyWithETH",
    stateMutability: "payable",
    inputs: [{ name: "minimumTokensOut", type: "uint256" }],
    outputs: [{ name: "tokensOut", type: "uint256" }],
  },
] as const;

export const uniswapQuoterV2Abi = [
  {
    type: "function",
    name: "quoteExactInput",
    stateMutability: "nonpayable",
    inputs: [
      { name: "path", type: "bytes" },
      { name: "amountIn", type: "uint256" },
    ],
    outputs: [
      { name: "amountOut", type: "uint256" },
      { name: "sqrtPriceX96AfterList", type: "uint160[]" },
      { name: "initializedTicksCrossedList", type: "uint32[]" },
      { name: "gasEstimate", type: "uint256" },
    ],
  },
] as const;

export function configuredChainId() {
  return configuredChain().id;
}

export function configuredChain() {
  return process.env.NEXT_PUBLIC_VOID_HOOD_TOKEN ? robinhoodChain : base;
}

export function configuredContractAddress() {
  return configuredTokenAddress();
}

export function configuredTokenAddress() {
  const address = process.env.NEXT_PUBLIC_VOID_HOOD_TOKEN ?? process.env.NEXT_PUBLIC_VOID_B20_ADDRESS;
  return address && isAddress(address) ? getAddress(address) : null;
}

export function configuredControllerAddress() {
  const address = process.env.NEXT_PUBLIC_VOID_HOOD_CONTROLLER ?? process.env.NEXT_PUBLIC_VOID_B20_CONTROLLER_ADDRESS;
  return address && isAddress(address) ? getAddress(address) : null;
}

export function configuredV2BuyRouterAddress() {
  const address = process.env.NEXT_PUBLIC_VOID_V2_BUY_ROUTER_ADDRESS;
  return address?.startsWith("0x") && address.length === 42 ? (address as `0x${string}`) : null;
}

export function configuredMarketVersion() {
  if (process.env.NEXT_PUBLIC_VOID_HOOD_TOKEN) return "hood";
  return configuredTokenAddress() ? "b20" : "unconfigured";
}

export function configuredExplorerName() {
  return configuredMarketVersion() === "hood" ? "ROBINHOOD BLOCKSCOUT" : "BASESCAN";
}

export function configuredMetadataFunction() {
  return "contractURI" as const;
}

export function zoraTradeUrl() {
  return null;
}

export function configuredCurveAddress() {
  const address = process.env.NEXT_PUBLIC_BONDING_CURVE_ADDRESS ?? process.env.NEXT_PUBLIC_VOID_CURVE_ADDRESS;
  return address?.startsWith("0x") && address.length === 42 ? (address as `0x${string}`) : MAINNET_VOID_CURVE_ADDRESS;
}

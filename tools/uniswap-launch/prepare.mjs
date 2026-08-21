import { createRequire } from "node:module";
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  createPublicClient,
  decodeFunctionData,
  encodeFunctionData,
  http,
  keccak256,
  parseAbi,
  stringToHex,
  zeroAddress,
} from "viem";
import { base } from "viem/chains";

const require = createRequire(import.meta.url);
const launcherSdk = require("@uniswap/liquidity-launcher-sdk");

const CHAIN_ID = 8453;
const SAFE = "0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9";
const TOKEN = "0xB2000000000000000000008f1878BE4d462Bd979";
const CONTROLLER = "0xaab614e99d804D9fAfCc35605791442bF120b71D";
const BURN_ADDRESS = "0x000000000000000000000000000000000000dEaD";
const TOKEN_SUPPLY = 1_000_000_000n * 10n ** 18n;
const RESERVED_FOR_LP = TOKEN_SUPPLY / 2n;
const SOLD_IN_AUCTION = TOKEN_SUPPLY - RESERVED_FOR_LP;
const AUCTION_DURATION_SECONDS = 4n * 60n * 60n;
const MIN_START_LEAD_SECONDS = 30n * 60n;
const MAX_START_LEAD_SECONDS = 24n * 60n * 60n;
const FLOOR_FDV_USD = 1_000;
const GRADUATION_FDV_USD = 10_000;
const POOL_FEE = 2_500;
const POOL_TICK_SPACING = 25;
const ZERO_BYTES32 = `0x${"00".repeat(32)}`;

const erc20Abi = parseAbi([
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
  "function approve(address,uint256) returns (bool)",
]);
const permit2Abi = parseAbi([
  "function allowance(address,address,address) view returns (uint160 amount,uint48 expiration,uint48 nonce)",
  "function approve(address token,address spender,uint160 amount,uint48 expiration)",
]);
const controllerAbi = parseAbi([
  "function renamePaused() view returns (bool)",
  "function token() view returns (address)",
]);
const lbpAbi = parseAbi([
  "function initializerFactory() view returns (address)",
]);
const safeAbi = parseAbi([
  "function getOwners() view returns (address[])",
  "function getThreshold() view returns (uint256)",
  "function nonce() view returns (uint256)",
]);

function fail(message) {
  throw new Error(message);
}

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) fail(`${name} is required`);
  return value;
}

function parsePositiveInteger(name) {
  const value = requiredEnv(name);
  if (!/^\d+$/.test(value)) fail(`${name} must be a positive integer`);
  const parsed = BigInt(value);
  if (parsed <= 0n) fail(`${name} must be greater than zero`);
  return parsed;
}

function parsePositiveNumber(name) {
  const value = Number(requiredEnv(name));
  if (!Number.isFinite(value) || value <= 0) fail(`${name} must be a positive number`);
  return value;
}

function json(value) {
  return `${JSON.stringify(value, (_, item) => (typeof item === "bigint" ? item.toString() : item), 2)}\n`;
}

function sameAddress(left, right) {
  return left.toLowerCase() === right.toLowerCase();
}

async function requireCode(client, label, address) {
  const code = await client.getCode({ address });
  if (!code || code === "0x") fail(`${label} has no code at ${address}`);
  return Math.max(0, (code.length - 2) / 2);
}

const rpcUrl = requiredEnv("BASE_MAINNET_RPC_URL");
const startTimeUnix = parsePositiveInteger("AUCTION_START_TIME_UNIX");
const ethUsdPrice = parsePositiveNumber("AUCTION_ETH_USD_PRICE");
const outputDirectory = resolve(process.env.AUCTION_OUTPUT_DIRECTORY || "tools/uniswap-launch");
const client = createPublicClient({ chain: base, transport: http(rpcUrl) });
const addresses = launcherSdk.getLauncherAddresses(CHAIN_ID);
if (!addresses) fail("The official launcher SDK has no Base deployment");

const block = await client.getBlock();
const chainId = await client.getChainId();
if (chainId !== CHAIN_ID) fail(`Expected Base chain ${CHAIN_ID}, received ${chainId}`);
if (startTimeUnix < block.timestamp + MIN_START_LEAD_SECONDS) {
  fail(`Auction start must be at least ${MIN_START_LEAD_SECONDS} seconds after the current Base block`);
}
if (startTimeUnix > block.timestamp + MAX_START_LEAD_SECONDS) {
  fail(`Auction start must be no more than ${MAX_START_LEAD_SECONDS} seconds after the current Base block`);
}

const endTimeUnix = startTimeUnix + AUCTION_DURATION_SECONDS;
const permit2Expiration = Number(endTimeUnix);
const blockTimeSeconds = launcherSdk.getBlockTimeSeconds(CHAIN_ID);
const blocks = launcherSdk.deriveBlocks({
  startTimeUnix,
  endTimeUnix,
  currentBlock: block.number,
  nowUnix: block.timestamp,
  blockTimeSeconds,
});

const [
  tokenDecimals,
  totalSupply,
  safeTokenBalance,
  erc20Allowance,
  permit2Allowance,
  renamePaused,
  controllerToken,
  initializerFactory,
  owners,
  threshold,
  safeNonce,
  launcherCodeBytes,
  lbpCodeBytes,
  ccaFactoryCodeBytes,
  permit2CodeBytes,
] = await Promise.all([
  client.readContract({ address: TOKEN, abi: erc20Abi, functionName: "decimals" }),
  client.readContract({ address: TOKEN, abi: erc20Abi, functionName: "totalSupply" }),
  client.readContract({ address: TOKEN, abi: erc20Abi, functionName: "balanceOf", args: [SAFE] }),
  client.readContract({ address: TOKEN, abi: erc20Abi, functionName: "allowance", args: [SAFE, addresses.permit2] }),
  client.readContract({
    address: addresses.permit2,
    abi: permit2Abi,
    functionName: "allowance",
    args: [SAFE, TOKEN, addresses.liquidityLauncher],
  }),
  client.readContract({ address: CONTROLLER, abi: controllerAbi, functionName: "renamePaused" }),
  client.readContract({ address: CONTROLLER, abi: controllerAbi, functionName: "token" }),
  client.readContract({ address: addresses.lbpStrategy, abi: lbpAbi, functionName: "initializerFactory" }),
  client.readContract({ address: SAFE, abi: safeAbi, functionName: "getOwners" }),
  client.readContract({ address: SAFE, abi: safeAbi, functionName: "getThreshold" }),
  client.readContract({ address: SAFE, abi: safeAbi, functionName: "nonce" }),
  requireCode(client, "LiquidityLauncher", addresses.liquidityLauncher),
  requireCode(client, "LBPStrategy", addresses.lbpStrategy),
  requireCode(client, "CCA factory", addresses.ccaFactory),
  requireCode(client, "Permit2", addresses.permit2),
]);

if (tokenDecimals !== 18) fail(`Expected 18 token decimals, received ${tokenDecimals}`);
if (totalSupply !== TOKEN_SUPPLY) fail(`Unexpected total supply ${totalSupply}`);
if (safeTokenBalance !== TOKEN_SUPPLY) fail(`Safe does not hold the full supply: ${safeTokenBalance}`);
if (!renamePaused) fail("Rename controller must remain paused during market launch preparation");
if (!sameAddress(controllerToken, TOKEN)) fail(`Controller points to unexpected token ${controllerToken}`);
if (!sameAddress(initializerFactory, addresses.ccaFactory)) {
  fail(`LBP strategy factory mismatch: ${initializerFactory}`);
}
if (erc20Allowance !== 0n) fail(`Expected zero ERC20-to-Permit2 allowance, received ${erc20Allowance}`);
if (permit2Allowance[0] !== 0n || permit2Allowance[1] !== 0) {
  fail(`Expected zero Permit2-to-launcher allowance, received ${permit2Allowance[0]}`);
}

const [poolAvailability] = await launcherSdk.getFeeTierAvailability(client, {
  chainId: CHAIN_ID,
  currency: zeroAddress,
  token: TOKEN,
  feeTiers: [{ feeAmount: POOL_FEE, tickSpacing: POOL_TICK_SPACING }],
});
if (!poolAvailability.available) {
  fail(`Intended v4 pool is unavailable: ${poolAvailability.reason}`);
}

const floorPricePerToken = launcherSdk.fdvUsdToPricePerToken(
  FLOOR_FDV_USD,
  1_000_000_000n,
  ethUsdPrice,
);
const graduationPricePerToken = launcherSdk.fdvUsdToPricePerToken(
  GRADUATION_FDV_USD,
  1_000_000_000n,
  ethUsdPrice,
);
const rawFloorPriceX96 = launcherSdk.floorPriceToX96(floorPricePerToken, 18, 18);
const { floorPriceX96, tickSpacing: auctionTickSpacing } = launcherSdk.deriveAuctionPricing(rawFloorPriceX96);
const graduationPriceX96 = launcherSdk.floorPriceToX96(graduationPricePerToken, 18, 18);
const requiredCurrencyRaised = launcherSdk.requiredCurrencyRaised(graduationPriceX96, SOLD_IN_AUCTION);
const auctionSteps = launcherSdk.deriveConvexAuctionSteps(blocks.startBlock, blocks.endBlock);
const auctionStepsData = launcherSdk.encodeAuctionSteps(auctionSteps);
const positionDefinitions = launcherSdk.buildPositionDefinitions(
  "FULL_RANGE",
  [],
  POOL_TICK_SPACING,
  zeroAddress,
  TOKEN,
);
const lpAllocationSchedule = launcherSdk.buildLpAllocationSchedule({ kind: "single", percent: 100 });

const auctionParams = {
  currency: zeroAddress,
  tokensRecipient: SAFE,
  // LBPStrategy must receive the raised currency so it can migrate it into the v4 pool.
  // Any migration remainder is returned to migratorParams.recipient (the Safe).
  fundsRecipient: addresses.lbpStrategy,
  startBlock: blocks.startBlock,
  endBlock: blocks.endBlock,
  claimBlock: blocks.claimBlock,
  tickSpacing: auctionTickSpacing,
  validationHook: zeroAddress,
  floorPrice: floorPriceX96,
  requiredCurrencyRaised,
  auctionStepsData,
};
const encodedAuctionParams = launcherSdk.encodeAuctionParams(auctionParams);
const migratorParams = {
  token: TOKEN,
  currency: zeroAddress,
  migrationBlock: blocks.migrationBlock,
  reservedTokenAmountForLP: RESERVED_FOR_LP,
  recipient: SAFE,
  positionRecipient: BURN_ADDRESS,
  poolParameters: { fee: POOL_FEE, tickSpacing: POOL_TICK_SPACING, hook: zeroAddress },
  positionDefinitions: launcherSdk.encodePositionDefinitions(positionDefinitions),
  lpAllocationSchedule: launcherSdk.encodeLpAllocationSchedule(lpAllocationSchedule),
};
const configData = launcherSdk.encodeConfigData(migratorParams, encodedAuctionParams);
const salt = keccak256(stringToHex(`VOIDCOIN-V4-BASE-${TOKEN}-${startTimeUnix}`));
if (salt === ZERO_BYTES32) fail("Derived salt cannot be zero");
const initializerSalt = launcherSdk.computeInitializerSalt(SAFE, salt, migratorParams);
const predictedAuctionAddress = await launcherSdk.predictAuctionAddress(client, {
  strategy: addresses.lbpStrategy,
  token: TOKEN,
  auctionSupply: SOLD_IN_AUCTION,
  auctionParams: encodedAuctionParams,
  initializerSalt,
});
const predictedAuctionCode = await client.getCode({ address: predictedAuctionAddress });
if (predictedAuctionCode && predictedAuctionCode !== "0x") {
  fail(`Predicted auction address is already deployed: ${predictedAuctionAddress}`);
}

const approvalTransactions = [
  {
    to: TOKEN,
    value: 0n,
    data: encodeFunctionData({
      abi: erc20Abi,
      functionName: "approve",
      args: [addresses.permit2, TOKEN_SUPPLY],
    }),
  },
  {
    to: addresses.permit2,
    value: 0n,
    data: encodeFunctionData({
      abi: permit2Abi,
      functionName: "approve",
      args: [TOKEN, addresses.liquidityLauncher, TOKEN_SUPPLY, permit2Expiration],
    }),
  },
];
const transactions = launcherSdk.buildLaunchTransactions({
  liquidityLauncher: addresses.liquidityLauncher,
  token: TOKEN,
  salt,
  acquire: { kind: "deposit", amount: TOKEN_SUPPLY },
  distributions: [{ strategy: addresses.lbpStrategy, amount: TOKEN_SUPPLY, configData }],
  approvals: approvalTransactions,
});
if (transactions.length !== 3) fail(`Expected three transactions, received ${transactions.length}`);

const decodedErc20Approval = decodeFunctionData({ abi: erc20Abi, data: transactions[0].data });
const decodedPermit2Approval = decodeFunctionData({ abi: permit2Abi, data: transactions[1].data });
const decodedLaunch = decodeFunctionData({ abi: launcherSdk.LIQUIDITY_LAUNCHER_ABI, data: transactions[2].data });
if (decodedErc20Approval.functionName !== "approve") fail("First transaction is not ERC20 approve");
if (decodedPermit2Approval.functionName !== "approve") fail("Second transaction is not Permit2 approve");
if (decodedLaunch.functionName !== "multicall") fail("Third transaction is not launcher multicall");

const preparedAt = Date.now();
const safeBuilder = {
  version: "1.0",
  chainId: String(CHAIN_ID),
  createdAt: preparedAt,
  meta: {
    name: "Create VOIDCOIN V4 Uniswap auction",
    description: `Atomic exact approvals and existing-token auction launch for ${TOKEN}`,
    txBuilderVersion: "1.18.0",
    createdFromSafeAddress: SAFE,
    createdFromOwnerAddress: "",
    checksum: "",
  },
  transactions: transactions.map((transaction) => ({
    to: transaction.to,
    value: transaction.value.toString(),
    data: transaction.data,
    contractMethod: null,
    contractInputsValues: null,
  })),
};

const receipt = {
  status: "PREPARED_NOT_EXECUTED",
  warning: "Review only. Importing does not authorize signing or execution.",
  preparedAt,
  officialSdk: {
    package: "@uniswap/liquidity-launcher-sdk",
    version: "1.11.0",
  },
  chain: {
    chainId,
    observedBlock: block.number,
    observedTimestamp: block.timestamp,
    blockTimeSeconds,
  },
  deployment: {
    safe: SAFE,
    token: TOKEN,
    controller: CONTROLLER,
    liquidityLauncher: addresses.liquidityLauncher,
    lbpStrategy: addresses.lbpStrategy,
    ccaFactory: addresses.ccaFactory,
    permit2: addresses.permit2,
    positionManager: addresses.positionManager,
    codeBytes: { launcherCodeBytes, lbpCodeBytes, ccaFactoryCodeBytes, permit2CodeBytes },
  },
  safeState: {
    owners,
    threshold,
    nonce: safeNonce,
    tokenBalance: safeTokenBalance,
    erc20ToPermit2Allowance: erc20Allowance,
    permit2ToLauncherAllowance: {
      amount: permit2Allowance[0],
      expiration: permit2Allowance[1],
      nonce: permit2Allowance[2],
    },
  },
  auction: {
    source: "existing-token",
    tokenDeposit: TOKEN_SUPPLY,
    soldSupply: SOLD_IN_AUCTION,
    reservedForLp: RESERVED_FOR_LP,
    currency: "native ETH",
    startTimeUnix,
    endTimeUnix,
    startBlock: blocks.startBlock,
    endBlock: blocks.endBlock,
    claimBlock: blocks.claimBlock,
    migrationBlock: blocks.migrationBlock,
    durationSeconds: AUCTION_DURATION_SECONDS,
    floorFdvUsd: FLOOR_FDV_USD,
    floorPricePerTokenEth: floorPricePerToken,
    graduationFdvUsd: GRADUATION_FDV_USD,
    graduationPricePerTokenEth: graduationPricePerToken,
    requiredCurrencyRaisedWei: requiredCurrencyRaised,
    ethUsdPrice,
    poolFeeHundredthsBip: POOL_FEE,
    poolTickSpacing: POOL_TICK_SPACING,
    poolId: poolAvailability.poolId,
    lpRange: "full-range",
    raisedFundsAllocatedToLpPercent: 100,
    poolOwnerAndRecoveryRecipient: SAFE,
    lpPositionRecipient: BURN_ADDRESS,
    lpPositionPolicy: "permanently burned",
    validationHook: zeroAddress,
    salt,
    initializerSalt,
    predictedAuctionAddress,
  },
  transactionPolicy: {
    atomicallyBundleable: true,
    transactionCount: transactions.length,
    erc20Approval: "exact 1,000,000,000 VOID to Permit2",
    permit2Approval: "exact 1,000,000,000 VOID to LiquidityLauncher; consumed by the same atomic batch",
    permit2Expiration,
    valueWei: "0",
    includesControllerUnpause: false,
  },
  safeBuilderFile: "safe-transaction-builder.json",
};

await mkdir(outputDirectory, { recursive: true });
await writeFile(resolve(outputDirectory, "safe-transaction-builder.json"), json(safeBuilder), { mode: 0o600 });
await writeFile(resolve(outputDirectory, "auction-preparation.json"), json(receipt), { mode: 0o600 });

console.log(`Prepared review-only auction artifacts in ${outputDirectory}`);
console.log(`Predicted auction: ${predictedAuctionAddress}`);
console.log(`Start: ${new Date(Number(startTimeUnix) * 1000).toISOString()}`);
console.log(`End: ${new Date(Number(endTimeUnix) * 1000).toISOString()}`);
console.log(`Safe transactions: ${transactions.length} (exact approval, exact Permit2 approval, launcher multicall)`);
console.log("No transaction was signed, proposed, or broadcast.");

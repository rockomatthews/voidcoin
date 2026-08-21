import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import {
  concatHex,
  createPublicClient,
  encodeFunctionData,
  http,
  padHex,
  parseAbi,
  size,
  toHex,
  zeroAddress,
} from "viem";
import { base } from "viem/chains";

const SAFE_MULTISEND = "0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761";
const outputDirectory = resolve(process.env.AUCTION_OUTPUT_DIRECTORY || "tools/uniswap-launch");
const forkRpcUrl = process.env.AUCTION_FORK_RPC_URL || "http://127.0.0.1:8546";
const parsedForkUrl = new URL(forkRpcUrl);
if (!['127.0.0.1', 'localhost', '::1'].includes(parsedForkUrl.hostname)) {
  throw new Error("AUCTION_FORK_RPC_URL must be a localhost-only private fork");
}

const safeAbi = parseAbi([
  "function getOwners() view returns (address[])",
  "function getThreshold() view returns (uint256)",
  "function nonce() view returns (uint256)",
  "function approveHash(bytes32)",
  "function getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256) view returns (bytes32)",
  "function execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes) returns (bool)",
]);
const multiSendAbi = parseAbi(["function multiSend(bytes transactions)"]);
const erc20Abi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address,address) view returns (uint256)",
]);
const permit2Abi = parseAbi([
  "function allowance(address,address,address) view returns (uint160 amount,uint48 expiration,uint48 nonce)",
]);
const controllerAbi = parseAbi(["function renamePaused() view returns (bool)"]);
const lbpAbi = parseAbi(["function registeredPoolIds(bytes32) view returns (address)"]);
const auctionAbi = parseAbi([
  "function token() view returns (address)",
  "function currency() view returns (address)",
  "function tokensRecipient() view returns (address)",
  "function fundsRecipient() view returns (address)",
  "function startBlock() view returns (uint64)",
  "function endBlock() view returns (uint64)",
]);

function sameAddress(left, right) {
  return left.toLowerCase() === right.toLowerCase();
}

function packMultiSendTransaction(transaction) {
  return concatHex([
    "0x00",
    transaction.to,
    padHex(toHex(BigInt(transaction.value)), { size: 32 }),
    padHex(toHex(size(transaction.data)), { size: 32 }),
    transaction.data,
  ]);
}

function prevalidatedSignature(owner) {
  return concatHex([padHex(owner, { size: 32 }), padHex("0x00", { size: 32 }), "0x01"]);
}

async function sendFrom(client, from, transaction) {
  const hash = await client.request({
    method: "eth_sendTransaction",
    params: [{ from, to: transaction.to, value: toHex(BigInt(transaction.value || 0)), data: transaction.data, gas: "0x1c9c380" }],
  });
  const receipt = await client.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`Private-fork transaction reverted: ${hash}`);
  return receipt;
}

const builderPath = resolve(outputDirectory, "safe-transaction-builder.json");
const preparationPath = resolve(outputDirectory, "auction-preparation.json");
const builderBytes = await readFile(builderPath);
const builder = JSON.parse(builderBytes);
const preparation = JSON.parse(await readFile(preparationPath, "utf8"));
const client = createPublicClient({ chain: base, transport: http(forkRpcUrl) });
if ((await client.getChainId()) !== 8453) throw new Error("Private fork must report Base chain ID 8453");

const safe = preparation.deployment.safe;
const token = preparation.deployment.token;
const permit2 = preparation.deployment.permit2;
const launcher = preparation.deployment.liquidityLauncher;
const strategy = preparation.deployment.lbpStrategy;
const controller = preparation.deployment.controller;
const auction = preparation.auction.predictedAuctionAddress;
const [owners, threshold, nonce, multiSendCode] = await Promise.all([
  client.readContract({ address: safe, abi: safeAbi, functionName: "getOwners" }),
  client.readContract({ address: safe, abi: safeAbi, functionName: "getThreshold" }),
  client.readContract({ address: safe, abi: safeAbi, functionName: "nonce" }),
  client.getCode({ address: SAFE_MULTISEND }),
]);
if (threshold !== 2n || owners.length !== 3) throw new Error("Unexpected Safe owner or threshold state");
if (!multiSendCode || multiSendCode === "0x") throw new Error("Canonical Safe MultiSend has no code");
if (builder.transactions.length !== 3) throw new Error("Expected exactly three prepared Safe transactions");

const packedTransactions = concatHex(builder.transactions.map(packMultiSendTransaction));
const multiSendData = encodeFunctionData({ abi: multiSendAbi, functionName: "multiSend", args: [packedTransactions] });
const safeTx = {
  to: SAFE_MULTISEND,
  value: 0n,
  data: multiSendData,
  operation: 1,
  safeTxGas: 8_000_000n,
  baseGas: 0n,
  gasPrice: 0n,
  gasToken: zeroAddress,
  refundReceiver: zeroAddress,
  nonce,
};
const safeTransactionHash = await client.readContract({
  address: safe,
  abi: safeAbi,
  functionName: "getTransactionHash",
  args: [
    safeTx.to,
    safeTx.value,
    safeTx.data,
    safeTx.operation,
    safeTx.safeTxGas,
    safeTx.baseGas,
    safeTx.gasPrice,
    safeTx.gasToken,
    safeTx.refundReceiver,
    safeTx.nonce,
  ],
});

const signingOwners = owners
  .slice(0, Number(threshold))
  .sort((left, right) => (BigInt(left) < BigInt(right) ? -1 : 1));
for (const owner of signingOwners) {
  await client.request({ method: "anvil_impersonateAccount", params: [owner] });
  await client.request({ method: "anvil_setBalance", params: [owner, "0x56bc75e2d63100000"] });
  const approvalData = encodeFunctionData({ abi: safeAbi, functionName: "approveHash", args: [safeTransactionHash] });
  await sendFrom(client, owner, { to: safe, value: "0", data: approvalData });
}
const signatures = concatHex(signingOwners.map(prevalidatedSignature));
const executionData = encodeFunctionData({
  abi: safeAbi,
  functionName: "execTransaction",
  args: [
    safeTx.to,
    safeTx.value,
    safeTx.data,
    safeTx.operation,
    safeTx.safeTxGas,
    safeTx.baseGas,
    safeTx.gasPrice,
    safeTx.gasToken,
    safeTx.refundReceiver,
    signatures,
  ],
});
const executionReceipt = await sendFrom(client, signingOwners[0], { to: safe, value: "0", data: executionData });

const [
  safeBalance,
  launcherBalance,
  strategyBalance,
  auctionBalance,
  erc20Allowance,
  permit2Allowance,
  controllerPaused,
  registeredAuction,
  auctionToken,
  auctionCurrency,
  tokensRecipient,
  fundsRecipient,
  auctionStartBlock,
  auctionEndBlock,
  finalSafeNonce,
] = await Promise.all([
  client.readContract({ address: token, abi: erc20Abi, functionName: "balanceOf", args: [safe] }),
  client.readContract({ address: token, abi: erc20Abi, functionName: "balanceOf", args: [launcher] }),
  client.readContract({ address: token, abi: erc20Abi, functionName: "balanceOf", args: [strategy] }),
  client.readContract({ address: token, abi: erc20Abi, functionName: "balanceOf", args: [auction] }),
  client.readContract({ address: token, abi: erc20Abi, functionName: "allowance", args: [safe, permit2] }),
  client.readContract({ address: permit2, abi: permit2Abi, functionName: "allowance", args: [safe, token, launcher] }),
  client.readContract({ address: controller, abi: controllerAbi, functionName: "renamePaused" }),
  client.readContract({ address: strategy, abi: lbpAbi, functionName: "registeredPoolIds", args: [preparation.auction.poolId] }),
  client.readContract({ address: auction, abi: auctionAbi, functionName: "token" }),
  client.readContract({ address: auction, abi: auctionAbi, functionName: "currency" }),
  client.readContract({ address: auction, abi: auctionAbi, functionName: "tokensRecipient" }),
  client.readContract({ address: auction, abi: auctionAbi, functionName: "fundsRecipient" }),
  client.readContract({ address: auction, abi: auctionAbi, functionName: "startBlock" }),
  client.readContract({ address: auction, abi: auctionAbi, functionName: "endBlock" }),
  client.readContract({ address: safe, abi: safeAbi, functionName: "nonce" }),
]);

const expectedSold = BigInt(preparation.auction.soldSupply);
const expectedReserve = BigInt(preparation.auction.reservedForLp);
if (safeBalance !== 0n || launcherBalance !== 0n) throw new Error("Safe or launcher retained VOID after launch");
if (strategyBalance !== expectedReserve || auctionBalance !== expectedSold) throw new Error("Auction token split mismatch");
if (erc20Allowance !== 0n || permit2Allowance[0] !== 0n) throw new Error("A launch allowance remained spendable");
if (!controllerPaused) throw new Error("Controller was unexpectedly unpaused");
if (!sameAddress(registeredAuction, auction)) throw new Error("Pool reservation does not point to predicted auction");
if (!sameAddress(auctionToken, token) || auctionCurrency !== zeroAddress) throw new Error("Auction asset mismatch");
if (!sameAddress(tokensRecipient, safe) || !sameAddress(fundsRecipient, strategy)) throw new Error("Auction recipient mismatch");
if (auctionStartBlock !== BigInt(preparation.auction.startBlock) || auctionEndBlock !== BigInt(preparation.auction.endBlock)) {
  throw new Error("Auction block window mismatch");
}
if (finalSafeNonce !== nonce + 1n) throw new Error("Safe nonce did not increment exactly once");

const simulation = {
  status: "PASS_PRIVATE_BASE_FORK_LIVE_PRECOMPILES",
  warning: "Private-fork evidence only. No Mainnet transaction was proposed, signed, or broadcast.",
  simulatedAt: Date.now(),
  builderSha256: createHash("sha256").update(builderBytes).digest("hex"),
  forkBlock: await client.getBlockNumber(),
  safeTransactionHash,
  forkExecutionTransactionHash: executionReceipt.transactionHash,
  gasUsed: executionReceipt.gasUsed,
  multiSend: SAFE_MULTISEND,
  operation: "delegatecall",
  safeNonceBefore: nonce,
  safeNonceAfter: finalSafeNonce,
  auction,
  postState: {
    safeTokenBalance: safeBalance,
    launcherTokenBalance: launcherBalance,
    strategyLpReserveBalance: strategyBalance,
    auctionSaleBalance: auctionBalance,
    erc20ToPermit2Allowance: erc20Allowance,
    permit2ToLauncherAllowance: {
      amount: permit2Allowance[0],
      expiration: permit2Allowance[1],
      nonce: permit2Allowance[2],
    },
    controllerPaused,
    registeredAuction,
    auctionToken,
    auctionCurrency,
    tokensRecipient,
    fundsRecipient,
    auctionStartBlock,
    auctionEndBlock,
  },
};
await writeFile(
  resolve(outputDirectory, "safe-fork-simulation.json"),
  `${JSON.stringify(simulation, (_, value) => (typeof value === "bigint" ? value.toString() : value), 2)}\n`,
  { mode: 0o600 },
);
console.log(JSON.stringify(simulation, (_, value) => (typeof value === "bigint" ? value.toString() : value), 2));

import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createPublicClient, decodeFunctionResult, http, keccak256, parseAbi } from "viem";
import { defineChain } from "viem";

const CHAIN_ID = 4663;
const RPC_URL = process.env.ROBINHOOD_MAINNET_RPC_URL?.trim() || "https://rpc.mainnet.chain.robinhood.com";
const EXPECTED_SAFE = "0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9";
const PROXY_FACTORY = "0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67";
const BASE_CREATION_TX = "0x61930498dd69dc716b475980e97474e0e947ebb6713d9d258cd33e00f0e64ee5";
const REPLAY_DATA = "0x1688f0b900000000000000000000000041675c099f32341bf84bfc5382af534df5c7461a0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001e4b63e800d00000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000bd89a1ce4dde368ffab0ec35506eece0b1ffdc540000000000000000000000000000000000000000000000000000000000000180000000000000000000000000fd0732dc9e303f09fcef3a7388ad10a83459ec99000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005afe7a11e700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000008a0182c099a618583e9ef98716dacf739b3bd94400000000000000000000000010944aed9ca4f39f4578f2c4538b38acd0d7f2b5000000000000000000000000ab58253c563313fee54c397f6aa877c715d8aa2c0000000000000000000000000000000000000000000000000000000000000024fe51f64300000000000000000000000029fcb43b46531bca003ddc8fcb67ffe91900c7620000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

const owners = [
  "0x8A0182c099A618583e9EF98716DAcF739b3BD944",
  "0x10944aed9cA4f39F4578f2C4538B38Acd0D7f2b5",
  "0xAb58253C563313feE54C397f6aA877C715d8aa2c",
];
const dependencies = [
  PROXY_FACTORY,
  "0x41675C099F32341bf84BFc5382aF534df5C7461a",
  "0xBD89A1CE4DDe368FFAB0eC35506eEcE0b1fFdc54",
  "0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99",
  "0x29fcb43b46531bca003ddc8fcb67ffe91900c762",
];
const expectedDependencyCodeHashes = [
  "0x50c3cdc4074750a7a974204a716c999edd37482f907608d960b2b025ee0b3317",
  "0x1fe2df852ba3299d6534ef416eefa406e56ced995bca886ab7a553e6d0c5e1c4",
  "0x2f25df28caf984366ee584e13241707e85dcd5a6ea0c14267928dafc1fd6274b",
  "0x7c6007a5d711cea8dfd5d91f5940ec29c7f200fe511eb1fc1397b367af3c42f9",
  "0xb1f926978a0f44a2c0ec8fe822418ae969bd8c3f18d61e5103100339894f81ff",
];
const chain = defineChain({
  id: CHAIN_ID,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
});
const client = createPublicClient({ chain, transport: http(RPC_URL) });
if (await client.getChainId() !== CHAIN_ID) throw new Error("wrong RPC chain");

const dependencyCode = await Promise.all(dependencies.map((address) => client.getBytecode({ address })));
if (dependencyCode.some((code) => !code)) throw new Error("a required Safe deployment contract has no code");
for (let index = 0; index < dependencyCode.length; index += 1) {
  if (keccak256(dependencyCode[index]) !== expectedDependencyCodeHashes[index]) {
    throw new Error(`Safe dependency ${dependencies[index]} bytecode does not match canonical v1.4.1`);
  }
}

const existingCode = await client.getBytecode({ address: EXPECTED_SAFE });
let simulation = EXPECTED_SAFE;
if (!existingCode) {
  const result = await client.call({ to: PROXY_FACTORY, data: REPLAY_DATA });
  if (!result.data) throw new Error("Safe replay simulation returned no data");
  simulation = decodeFunctionResult({
    abi: parseAbi(["function createProxyWithNonce(address singleton,bytes initializer,uint256 saltNonce) returns(address proxy)"]),
    functionName: "createProxyWithNonce",
    data: result.data,
  });
  if (simulation.toLowerCase() !== EXPECTED_SAFE.toLowerCase()) throw new Error("Safe replay predicts the wrong address");
}

const receipt = {
  status: existingCode ? "SAFE_ALREADY_DEPLOYED" : "PREPARED_NOT_EXECUTED",
  warning: "This is an EOA wallet transaction that creates the Robinhood-chain Safe. Nothing was broadcast.",
  chainId: CHAIN_ID,
  expectedSafe: EXPECTED_SAFE,
  expectedOwners: owners,
  expectedThreshold: 2,
  proxyFactory: PROXY_FACTORY,
  sourceBaseCreationTransaction: BASE_CREATION_TX,
  simulation,
  dependencyCodeHashes: Object.fromEntries(dependencies.map((address, index) => [address, expectedDependencyCodeHashes[index]])),
  transaction: existingCode ? null : { to: PROXY_FACTORY, value: "0", data: REPLAY_DATA },
};

const outputDir = resolve("tools/hood-launch");
await mkdir(outputDir, { recursive: true });
await writeFile(resolve(outputDir, "safe-replay-preparation.json"), `${JSON.stringify(receipt, null, 2)}\n`);
console.log(JSON.stringify(receipt, null, 2));

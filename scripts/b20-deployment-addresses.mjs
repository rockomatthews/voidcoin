import { createPublicClient, getAddress, getContractAddress, http, isHex } from "viem";
import { base } from "viem/chains";

export const B20_FACTORY_ADDRESS = "0xB20f000000000000000000000000000000000000";
const factoryAbi = [{
  type: "function",
  name: "getB20Address",
  stateMutability: "view",
  inputs: [
    { name: "variant", type: "uint8" },
    { name: "sender", type: "address" },
    { name: "salt", type: "bytes32" },
  ],
  outputs: [{ name: "token", type: "address" }],
}];

export async function b20PredictionFromEnvironment() {
  const deployerValue = process.env.DEPLOYER_ADDRESS?.trim();
  const rpcUrl = process.env.BASE_MAINNET_RPC_URL?.trim();
  const salt = process.env.VOID_B20_SALT?.trim();
  if (!deployerValue) throw new Error("DEPLOYER_ADDRESS is required (public address only)");
  if (!rpcUrl) throw new Error("BASE_MAINNET_RPC_URL is required");
  if (!salt || !isHex(salt) || salt.length !== 66 || /^0x0{64}$/i.test(salt)) {
    throw new Error("VOID_B20_SALT must be a nonzero bytes32 hex value");
  }

  const client = createPublicClient({ chain: base, transport: http(rpcUrl) });
  const chainId = await client.getChainId();
  if (chainId !== base.id) throw new Error(`BASE_MAINNET_RPC_URL returned chain ${chainId}; expected ${base.id}`);
  const deployer = getAddress(deployerValue);
  const nonce = await client.getTransactionCount({ address: deployer, blockTag: "pending" });
  const bootstrapper = getContractAddress({ from: deployer, nonce });
  const controller = getContractAddress({ from: bootstrapper, nonce: 1n });
  const token = await client.readContract({
    address: B20_FACTORY_ADDRESS,
    abi: factoryAbi,
    functionName: "getB20Address",
    args: [0, bootstrapper, salt],
  });

  return {
    chainId,
    deployer,
    deployerNonce: nonce.toString(),
    bootstrapper,
    controller,
    token: getAddress(token),
    salt,
    factory: getAddress(B20_FACTORY_ADDRESS),
  };
}

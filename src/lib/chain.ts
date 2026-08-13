import { createPublicClient, http } from "viem";
import { configuredChain } from "./contract";

export function getPublicClient() {
  const chain = configuredChain();
  const rpc = chain.id === 8453 ? process.env.BASE_MAINNET_RPC_URL : process.env.BASE_SEPOLIA_RPC_URL;
  return createPublicClient({ chain, transport: http(rpc || chain.rpcUrls.default.http[0]) });
}

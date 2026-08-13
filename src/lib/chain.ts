import { createPublicClient, http } from "viem";
import { configuredChain } from "./contract";

export function getPublicClient() {
  const chain = configuredChain();
  return createPublicClient({ chain, transport: http(process.env.BASE_MAINNET_RPC_URL || chain.rpcUrls.default.http[0]) });
}

import { createPublicClient, http } from "viem";
import { configuredChain } from "./contract";

export function getPublicClient() {
  const chain = configuredChain();
  const rpcUrl = chain.id === 4663 ? process.env.ROBINHOOD_MAINNET_RPC_URL : process.env.BASE_MAINNET_RPC_URL;
  return createPublicClient({ chain, transport: http(rpcUrl || chain.rpcUrls.default.http[0]) });
}

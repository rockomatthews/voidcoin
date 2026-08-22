"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { base } from "wagmi/chains";
import { coinbaseWallet, injected, walletConnect } from "wagmi/connectors";
import { robinhoodChain } from "@/lib/contract";

const walletConnectProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID;

const wagmiConfig = createConfig({
  chains: [base, robinhoodChain],
  connectors: [
    injected(),
    coinbaseWallet({ appName: "VOIDCOIN", appLogoUrl: "https://voidcoin.fun/voidcoin-logo.png" }),
    ...(walletConnectProjectId ? [walletConnect({ projectId: walletConnectProjectId, showQrModal: true })] : []),
  ],
  transports: {
    [base.id]: http(),
    [robinhoodChain.id]: http(robinhoodChain.rpcUrls.default.http[0]),
  },
  ssr: true,
});

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}

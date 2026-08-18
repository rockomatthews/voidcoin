"use client";

import { useAccount, useConnect, useDisconnect } from "wagmi";
import { shortAddress } from "@/lib/site";

export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <button className="wallet-button connected" type="button" onClick={() => disconnect()} aria-label="Disconnect wallet">
        <span className="wallet-pulse" />
        {shortAddress(address)}
      </button>
    );
  }

  return (
    <details className="wallet-menu">
      <summary className="wallet-button">{isPending ? "CONNECTING" : "CONNECT WALLET"}</summary>
      <div className="wallet-menu-options">
        {connectors.map((connector) => (
          <button type="button" disabled={isPending} onClick={() => connect({ connector })} key={connector.uid}>
            {connector.id === "walletConnect" ? "WALLETCONNECT / QR" : connector.name === "Injected" ? "BROWSER / BASE APP" : connector.name.toUpperCase()}
          </button>
        ))}
      </div>
    </details>
  );
}

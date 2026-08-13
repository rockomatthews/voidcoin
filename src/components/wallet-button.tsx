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
    <button className="wallet-button" type="button" disabled={isPending || connectors.length === 0} onClick={() => connectors[0] && connect({ connector: connectors[0] })}>
      {isPending ? "CONNECTING" : "CONNECT WALLET"}
    </button>
  );
}

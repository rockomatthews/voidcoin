"use client";

import { useState, type FormEvent } from "react";
import { formatUnits, parseEther } from "viem";
import { useAccount, useChainId, usePublicClient, useSwitchChain, useWriteContract } from "wagmi";
import { configuredBondingCurveAddress, configuredChainId, voidBondingCurveAbi } from "@/lib/contract";

export function BuyVoid() {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const targetChainId = configuredChainId();
  const curveAddress = configuredBondingCurveAddress();
  const client = usePublicClient({ chainId: targetChainId });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const [quote, setQuote] = useState("Enter an ETH amount to preview your VOID.");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!curveAddress || !client || !isConnected) return;
    const form = new FormData(event.currentTarget);
    try {
      setBusy(true);
      const value = parseEther(String(form.get("eth") ?? "0"));
      if (value <= 0n) throw new Error("Enter an ETH amount greater than zero.");
      if (chainId !== targetChainId) await switchChainAsync({ chainId: targetChainId });
      const tokensOut = await client.readContract({ address: curveAddress, abi: voidBondingCurveAbi, functionName: "quoteBuy", args: [value] });
      const minimumOut = tokensOut * 99n / 100n;
      setQuote(`Wallet confirmation: approximately ${Number(formatUnits(tokensOut, 18)).toLocaleString("en-US", { maximumFractionDigits: 0 })} VOID.`);
      const hash = await writeContractAsync({ address: curveAddress, abi: voidBondingCurveAbi, functionName: "buy", args: [minimumOut], value, chainId: targetChainId });
      setQuote("Purchase submitted. Waiting for Base confirmation…");
      await client.waitForTransactionReceipt({ hash });
      setQuote("VOID acquired. You can now challenge the burn record.");
    } catch (error) {
      setQuote(error instanceof Error ? error.message : "Purchase could not be completed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="buy-panel" aria-labelledby="buy-title">
      <div><span className="eyebrow">CONTINUOUS MARKET</span><h2 id="buy-title">BUY VOID</h2><p>The curve stays open. More demand raises the price.</p></div>
      <form onSubmit={submit}>
        <label><span>ETH ON BASE</span><input name="eth" inputMode="decimal" placeholder="0.01" required /></label>
        <button className="primary-action" disabled={!curveAddress || !isConnected || busy}>{!curveAddress ? "CURVE DEPLOYMENT REQUIRED" : !isConnected ? "CONNECT WALLET TO BUY" : busy ? "PROCESSING…" : "BUY VOID"}</button>
        <small aria-live="polite">{quote}</small>
      </form>
    </section>
  );
}

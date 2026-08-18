"use client";

import { useEffect, useState, type FormEvent } from "react";
import { formatUnits, parseEther } from "viem";
import { useAccount, useChainId, usePublicClient, useSwitchChain, useWriteContract } from "wagmi";
import { WalletButton } from "@/components/wallet-button";
import { configuredChainId, configuredCurveAddress, voidBondingCurveAbi } from "@/lib/contract";
import { minimumTokensOut } from "@/lib/purchase";

type Quote = {
  graduated: boolean;
  ethReserve: string;
  graduationThreshold: string;
  progress: number;
  maxBuyEth: string;
  tokensOut: string;
  tokensOutWei: string;
  uniswapUrl: string;
};

type Phase = "idle" | "switching" | "confirming" | "complete" | "error";

const presets = ["0.05", "0.1", "0.25", "0.5", "1"];

function purchaseError(error: unknown) {
  const message = error instanceof Error ? error.message : "The purchase could not be completed.";
  if (/user rejected|user denied|rejected the request/i.test(message)) return "Purchase cancelled in your wallet.";
  if (/insufficient funds/i.test(message)) return "Your wallet does not have enough ETH for this purchase and Base gas.";
  if (/slippage|minimum.*out/i.test(message)) return "The price moved beyond the 1% protection limit. Refresh the quote and try again.";
  return message;
}

export function BuyVoid({ symbol }: { symbol: string }) {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const targetChainId = configuredChainId();
  const curveAddress = configuredCurveAddress();
  const publicClient = usePublicClient({ chainId: targetChainId });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const [amount, setAmount] = useState("0.11");
  const [quote, setQuote] = useState<Quote | null>(null);
  const [quoteError, setQuoteError] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [message, setMessage] = useState("Enter an amount to receive a live Base quote.");
  const [transactionHash, setTransactionHash] = useState<`0x${string}` | null>(null);
  const [quoteVersion, setQuoteVersion] = useState(0);

  useEffect(() => {
    const interval = window.setInterval(() => setQuoteVersion((current) => current + 1), 10_000);
    return () => window.clearInterval(interval);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    const timeout = window.setTimeout(() => {
      fetch(`/api/curve?eth=${encodeURIComponent(amount)}`, { signal: controller.signal, cache: "no-store" })
        .then(async (response) => {
          const result = await response.json();
          if (!response.ok) throw new Error(result.error ?? "Quote unavailable");
          return result as Quote;
        })
        .then((result) => { setQuote(result); setQuoteError(""); })
        .catch((error) => {
          if (error instanceof DOMException && error.name === "AbortError") return;
          setQuote(null);
          setQuoteError(error instanceof Error ? error.message : "Quote unavailable");
        });
    }, 250);
    return () => { controller.abort(); window.clearTimeout(timeout); };
  }, [amount, quoteVersion]);

  async function buy(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!isConnected || !publicClient || !quote || quote.graduated) return;
    try {
      setTransactionHash(null);
      if (chainId !== targetChainId) {
        setPhase("switching");
        setMessage("Switching your wallet to Base Mainnet.");
        await switchChainAsync({ chainId: targetChainId });
      }
      const value = parseEther(amount);
      const quotedTokens = BigInt(quote.tokensOutWei);
      if (quotedTokens <= 0n) throw new Error("This amount does not produce a valid token quote.");
      setPhase("confirming");
      setMessage(`Confirm the ${amount} ETH purchase in your wallet.`);
      const hash = await writeContractAsync({
        address: curveAddress,
        abi: voidBondingCurveAbi,
        functionName: "buy",
        args: [minimumTokensOut(quotedTokens), BigInt(Math.floor(Date.now() / 1_000) + 600)],
        value,
        chainId: targetChainId,
      });
      setTransactionHash(hash);
      setMessage("Purchase submitted. Waiting for Base confirmation.");
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("The purchase reverted on Base.");
      setPhase("complete");
      setMessage(`${Number(formatUnits(quotedTokens, 18)).toLocaleString("en-US", { maximumFractionDigits: 0 })} ${symbol} purchased. Your wallet balance will update after indexing.`);
      setQuoteVersion((current) => current + 1);
    } catch (error) {
      setPhase("error");
      setMessage(purchaseError(error));
    }
  }

  if (quote?.graduated) {
    return (
      <section className="buy-void graduated" aria-label={`Buy ${symbol}`}>
        <div><span>LIVE MARKET</span><strong>{symbol} HAS GRADUATED</strong><small>Trading now continues on Base through Uniswap.</small></div>
        <a className="buy-action" href={quote.uniswapUrl} target="_blank" rel="noreferrer">BUY {symbol} ON UNISWAP ↗</a>
      </section>
    );
  }

  const tokens = quote ? Number(quote.tokensOut) : 0;
  const busy = phase === "switching" || phase === "confirming";

  return (
    <form className="buy-void" aria-label={`Buy ${symbol}`} onSubmit={buy}>
      <div className="buy-head">
        <div><span>BUY ON BASE</span><strong>BUY {symbol}</strong></div>
        <WalletButton />
      </div>
      <div className="buy-fields">
        <label><span>YOU PAY</span><div className="buy-input"><input value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" type="number" min="0.000001" max="1" step="0.001" aria-label="ETH purchase amount" /><b>ETH</b></div></label>
        <div className="buy-arrow" aria-hidden="true">→</div>
        <div className="buy-output"><span>YOU RECEIVE — EST.</span><strong>{quote ? tokens.toLocaleString("en-US", { maximumFractionDigits: 0 }) : "—"}</strong><b>{symbol}</b></div>
      </div>
      <div className="buy-presets" role="group" aria-label="ETH amount presets">
        {presets.map((preset) => <button type="button" className={amount === preset ? "active" : ""} onClick={() => setAmount(preset)} key={preset}>{preset} ETH</button>)}
      </div>
      <div className="buy-progress"><div><span>LAUNCH PROGRESS</span><b>{quote ? `${quote.ethReserve} / ${quote.graduationThreshold} ETH` : "READING BASE…"}</b></div><i><span style={{ width: `${quote?.progress ?? 0}%` }} /></i></div>
      <p className={`buy-status phase-${phase}`} aria-live="polite">{quoteError || message}{transactionHash ? <> <a href={`https://basescan.org/tx/${transactionHash}`} target="_blank" rel="noreferrer">VIEW TRANSACTION ↗</a></> : null}</p>
      {isConnected ? <button className="buy-action" type="submit" disabled={!quote || Boolean(quoteError) || busy}>{busy ? "CONFIRMING…" : `BUY ${symbol}`}</button> : <p className="buy-connect-hint">Connect a wallet above to buy. Maximum 1 ETH per transaction. The displayed quote includes the 1% trading fee and has 1% price-movement protection.</p>}
    </form>
  );
}

"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { formatEther, formatUnits, parseEther } from "viem";
import { useAccount, useChainId, usePublicClient, useSwitchChain, useWriteContract } from "wagmi";
import { WalletButton } from "@/components/wallet-button";
import { configuredChainId, configuredV2BuyRouterAddress, voidV2BuyRouterAbi } from "@/lib/contract";
import { minimumTokensOut } from "@/lib/purchase";

type Quote = { tokensOut: string; tokensOutWei: string; ethIn: string };
type Phase = "idle" | "switching" | "confirming" | "complete" | "error";

const presets = ["0.0005", "0.001", "0.005", "0.01"];

function purchaseError(error: unknown) {
  const message = error instanceof Error ? error.message : "The purchase could not be completed.";
  if (/user rejected|user denied|rejected the request/i.test(message)) return "Purchase cancelled in your wallet.";
  if (/insufficient funds/i.test(message)) return "Your wallet does not have enough ETH for this purchase and Base gas.";
  if (/slippage|minimum.*out|too little received/i.test(message)) return "The market moved beyond the 1% protection limit. Refresh and try again.";
  return message;
}

export function BuyVoidV2({ symbol, nextBurn }: { symbol: string; nextBurn: number }) {
  const { isConnected } = useAccount();
  const chainId = useChainId();
  const targetChainId = configuredChainId();
  const buyRouter = configuredV2BuyRouterAddress();
  const publicClient = usePublicClient({ chainId: targetChainId });
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const [amount, setAmount] = useState("0.0005");
  const [quote, setQuote] = useState<Quote | null>(null);
  const [quoteError, setQuoteError] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [message, setMessage] = useState("Enter any ETH amount for a live Uniswap quote.");
  const [transactionHash, setTransactionHash] = useState<`0x${string}` | null>(null);
  const [quoteVersion, setQuoteVersion] = useState(0);

  useEffect(() => {
    const interval = window.setInterval(() => setQuoteVersion((current) => current + 1), 10_000);
    return () => window.clearInterval(interval);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    const timeout = window.setTimeout(() => {
      fetch(`/api/v2/quote?eth=${encodeURIComponent(amount)}`, { signal: controller.signal, cache: "no-store" })
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

  const takeoverEth = useMemo(() => {
    if (!quote) return null;
    const output = Number(quote.tokensOut);
    const input = Number(quote.ethIn);
    if (!Number.isFinite(output) || output <= 0 || !Number.isFinite(input)) return null;
    return input * nextBurn / output;
  }, [nextBurn, quote]);

  async function buy(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!isConnected || !publicClient || !quote || !buyRouter) return;
    try {
      setTransactionHash(null);
      if (chainId !== targetChainId) {
        setPhase("switching");
        setMessage("Switching your wallet to Base Mainnet.");
        await switchChainAsync({ chainId: targetChainId });
      }
      const value = parseEther(amount);
      const quotedTokens = BigInt(quote.tokensOutWei);
      if (value <= 0n || quotedTokens <= 0n) throw new Error("Enter an ETH amount greater than zero.");
      setPhase("confirming");
      setMessage(`Confirm the ${amount} ETH purchase in your wallet.`);
      const hash = await writeContractAsync({
        address: buyRouter,
        abi: voidV2BuyRouterAbi,
        functionName: "buyWithETH",
        args: [minimumTokensOut(quotedTokens)],
        value,
        chainId: targetChainId,
      });
      setTransactionHash(hash);
      setMessage("Purchase submitted. Waiting for Base confirmation.");
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("The purchase reverted on Base.");
      setPhase("complete");
      setMessage(`${Number(formatUnits(quotedTokens, 18)).toLocaleString("en-US", { maximumFractionDigits: 0 })} ${symbol} purchased.`);
      setQuoteVersion((current) => current + 1);
    } catch (error) {
      setPhase("error");
      setMessage(purchaseError(error));
    }
  }

  const tokens = quote ? Number(quote.tokensOut) : 0;
  const busy = phase === "switching" || phase === "confirming";

  return (
    <form className="buy-void buy-void-v2" aria-label={`Buy ${symbol}`} onSubmit={buy}>
      <div className="buy-head">
        <div><span>LIVE UNISWAP MARKET / BASE</span><strong>BUY {symbol}</strong></div>
        <WalletButton />
      </div>
      <div className="buy-fields">
        <label><span>YOU PAY — ANY AMOUNT</span><div className="buy-input"><input value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" type="number" min="0.000000000000000001" step="any" required aria-label="ETH purchase amount" /><b>ETH</b></div></label>
        <div className="buy-arrow" aria-hidden="true">→</div>
        <div className="buy-output"><span>YOU RECEIVE — EST.</span><strong>{quote ? tokens.toLocaleString("en-US", { maximumFractionDigits: 0 }) : "—"}</strong><b>{symbol}</b></div>
      </div>
      <div className="buy-presets" role="group" aria-label="ETH amount presets">
        {presets.map((preset) => <button type="button" className={amount === preset ? "active" : ""} onClick={() => setAmount(preset)} key={preset}>{preset} ETH</button>)}
      </div>
      <div className="buy-progress v2-market-line"><div><span>EST. ETH TO REACH THE NEXT BURN</span><b>{takeoverEth === null ? "READING MARKET…" : `${Number(formatEther(parseEther(takeoverEth.toFixed(18)))).toLocaleString("en-US", { maximumSignificantDigits: 4 })} ETH`}</b></div><i><span style={{ width: "100%" }} /></i></div>
      <p className={`buy-status phase-${phase}`} aria-live="polite">{quoteError || message}{transactionHash ? <> <a href={`https://basescan.org/tx/${transactionHash}`} target="_blank" rel="noreferrer">VIEW TRANSACTION ↗</a></> : null}</p>
      {isConnected ? <button className="buy-action" type="submit" disabled={!quote || Boolean(quoteError) || busy || !buyRouter}>{busy ? "CONFIRMING…" : `BUY ${symbol}`}</button> : <p className="buy-connect-hint">Connect a wallet to buy through the live Uniswap market. There is no graduation and no site-only balance.</p>}
    </form>
  );
}

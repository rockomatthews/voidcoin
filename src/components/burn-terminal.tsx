"use client";

import { useState, type FormEvent } from "react";
import { useAccount, useChainId, usePublicClient, useSignMessage, useSwitchChain, useWriteContract } from "wagmi";
import { configuredChainId, configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { BURN_AMOUNT, formatNumber } from "@/lib/site";

type Phase = "idle" | "signing" | "preparing" | "burning" | "confirming" | "complete" | "error";

export function BurnTerminal() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const targetChainId = configuredChainId();
  const contractAddress = configuredContractAddress();
  const publicClient = usePublicClient({ chainId: targetChainId });
  const { switchChainAsync } = useSwitchChain();
  const { signMessageAsync } = useSignMessage();
  const { writeContractAsync } = useWriteContract();
  const [phase, setPhase] = useState<Phase>("idle");
  const [message, setMessage] = useState("Fill the chamber to prepare a private commitment.");
  const [accepted, setAccepted] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!address || !contractAddress || !publicClient) return;
    const formElement = event.currentTarget;
    const values = new FormData(formElement);
    try {
      if (chainId !== targetChainId) await switchChainAsync({ chainId: targetChainId });
      setPhase("signing");
      setMessage("Sign the private proposal challenge. This signature does not spend tokens.");
      const challengeResponse = await fetch("/api/auth/challenge", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ wallet: address }) });
      const challenge = await challengeResponse.json();
      if (!challengeResponse.ok) throw new Error(challenge.error ?? "Could not create wallet challenge");
      const signature = await signMessageAsync({ message: challenge.message });

      setPhase("preparing");
      setMessage("Sanitizing the private image and binding the proposal to the next burn slot.");
      values.set("wallet", address);
      values.set("message", challenge.message);
      values.set("challengeToken", challenge.token);
      values.set("signature", signature);
      const requestResponse = await fetch("/api/requests", { method: "POST", body: values });
      const prepared = await requestResponse.json();
      if (!requestResponse.ok) throw new Error(prepared.error ?? "Could not prepare proposal");

      setPhase("burning");
      setMessage(`Confirm the permanent burn of ${formatNumber(BURN_AMOUNT)} VOID in your wallet.`);
      const isReplacement = prepared.mode === "replace";
      const transactionHash = await writeContractAsync({ address: contractAddress, abi: voidCoinAbi, functionName: isReplacement ? "replaceCommitment" : "burnForRename", args: [prepared.commitment], chainId: targetChainId });

      setPhase("confirming");
      setMessage("Burn submitted. Waiting for Base confirmation and moderation intake.");
      await publicClient.waitForTransactionReceipt({ hash: transactionHash });
      const confirmResponse = await fetch(`/api/requests/${prepared.requestId}/confirm`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ transactionHash, mode: prepared.mode }) });
      const confirmed = await confirmResponse.json();
      if (!confirmResponse.ok) throw new Error(confirmed.error ?? "The burn confirmed but intake verification needs attention");

      setPhase("complete");
      setMessage(isReplacement ? "Replacement verified. The moderator has the new private submission; the original deadline is unchanged." : "Burn verified. The moderator has been notified; this slot expires in 72 hours.");
      formElement.reset();
      setAccepted(false);
    } catch (error) {
      setPhase("error");
      setMessage(error instanceof Error ? error.message : "The rename request could not be completed");
    }
  }

  const disabledReason = !contractAddress
    ? "The Base Sepolia contract has not been deployed yet. The interface is ready for review."
    : !isConnected
      ? "Connect a wallet to enter the chamber."
      : !accepted
        ? "Acknowledge the irreversible burn first."
        : null;

  return (
    <form className="burn-terminal" onSubmit={submit}>
      <div className="terminal-head">
        <div>
          <span className="eyebrow">PRIVATE PROPOSAL CHANNEL</span>
          <h2>AUTHOR THE NEXT SKIN</h2>
        </div>
        <span className="terminal-code">72H / 0.1%</span>
      </div>
      <div className="field-grid">
        <label>
          <span>NEW NAME</span>
          <input name="name" required maxLength={15} pattern="[A-Za-z0-9]+( [A-Za-z0-9]+)*" placeholder="NIGHT SHIFT" autoComplete="off" />
          <small>1–15 letters or numbers, single spaces only.</small>
        </label>
        <label>
          <span>NEW TICKER</span>
          <div className="ticker-input"><b>$</b><input name="symbol" required maxLength={10} pattern="[A-Za-z0-9]+" placeholder="NIGHT" autoComplete="off" /></div>
          <small>1–10 letters or numbers, case-sensitive.</small>
        </label>
        <label>
          <span>STATUS EMAIL <em>OPTIONAL</em></span>
          <input name="email" type="email" placeholder="burner@example.com" autoComplete="email" />
          <small>Used only for this moderation request.</small>
        </label>
        <label>
          <span>NEW IMAGE</span>
          <input name="image" type="file" required accept="image/png,image/jpeg,image/gif" />
          <small>Decoded PNG, JPEG, or GIF. 2 MB / 2048 px maximum.</small>
        </label>
      </div>
      <label className="burn-warning">
        <input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)} />
        <span><strong>THE BURN CANNOT BE REFUNDED.</strong> Rejection, expiry, a failed resubmission, or third-party metadata caching does not restore the {formatNumber(BURN_AMOUNT)} tokens.</span>
      </label>
      <div className={`terminal-status phase-${phase}`} aria-live="polite"><span />{message}</div>
      <button className="primary-action" type="submit" disabled={Boolean(disabledReason) || phase === "burning" || phase === "confirming" || phase === "preparing" || phase === "signing"} title={disabledReason ?? undefined}>
        {contractAddress ? `BURN ${formatNumber(BURN_AMOUNT)} VOID + SUBMIT` : "SEPOLIA DEPLOYMENT REQUIRED"}
      </button>
    </form>
  );
}

"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useAccount, useChainId, usePublicClient, useSignMessage, useSwitchChain, useWriteContract } from "wagmi";
import { configuredChainId, configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { MINIMUM_BURN_INCREMENT, formatNumber } from "@/lib/site";

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
  const [minimumBurn, setMinimumBurn] = useState(MINIMUM_BURN_INCREMENT);
  const [burnAmount, setBurnAmount] = useState(String(MINIMUM_BURN_INCREMENT));

  useEffect(() => {
    const controller = new AbortController();
    fetch("/api/state", { signal: controller.signal })
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("state unavailable")))
      .then((state: { nextBurnAmount?: number }) => {
        const next = state.nextBurnAmount ?? MINIMUM_BURN_INCREMENT;
        setMinimumBurn(next);
        setBurnAmount(String(next));
      })
      .catch(() => undefined);
    return () => controller.abort();
  }, []);

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
      setMessage("Sanitizing the private image and binding the proposal to the current record challenge.");
      values.set("wallet", address);
      values.set("message", challenge.message);
      values.set("challengeToken", challenge.token);
      values.set("signature", signature);
      const requestResponse = await fetch("/api/requests", { method: "POST", body: values });
      const prepared = await requestResponse.json();
      if (!requestResponse.ok) throw new Error(prepared.error ?? "Could not prepare proposal");

      setPhase("burning");
      const isReplacement = prepared.mode === "replace";
      const burnAmountWei = BigInt(prepared.burnAmount);
      setMessage(isReplacement ? "Confirm the replacement proposal. No additional burn is required." : `Confirm the permanent burn of ${formatNumber(Number(burnAmountWei / 10n ** 18n))} VOID in your wallet.`);
      const transactionHash = isReplacement
        ? await writeContractAsync({ address: contractAddress, abi: voidCoinAbi, functionName: "replaceCommitment", args: [prepared.commitment], chainId: targetChainId })
        : await writeContractAsync({ address: contractAddress, abi: voidCoinAbi, functionName: "burnForRename", args: [burnAmountWei, prepared.commitment], chainId: targetChainId });

      setPhase("confirming");
      setMessage("Burn submitted. Waiting for Base confirmation and moderation intake.");
      await publicClient.waitForTransactionReceipt({ hash: transactionHash });
      const confirmResponse = await fetch(`/api/requests/${prepared.requestId}/confirm`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ transactionHash, mode: prepared.mode }) });
      const confirmed = await confirmResponse.json();
      if (!confirmResponse.ok) throw new Error(confirmed.error ?? "The burn confirmed but intake verification needs attention");

      setPhase("complete");
      setMessage(isReplacement ? "Replacement verified. The moderator has the new private submission." : "New burn record verified. The moderator has been notified. You remain in control unless a higher record replaces yours.");
      formElement.reset();
      if (!isReplacement) {
        const next = Number(burnAmountWei / 10n ** 18n) + MINIMUM_BURN_INCREMENT;
        setMinimumBurn(next);
        setBurnAmount(String(next));
      }
      setAccepted(false);
    } catch (error) {
      setPhase("error");
      setMessage(error instanceof Error ? error.message : "The rename request could not be completed");
    }
  }

  const disabledReason = !contractAddress
    ? "The Base Mainnet contract has not been deployed yet."
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
        <span className="terminal-code">RECORD + {formatNumber(MINIMUM_BURN_INCREMENT)}</span>
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
          <span>YOUR BURN RECORD</span>
          <input name="burnAmount" type="number" required min={minimumBurn} step="1" value={burnAmount} onChange={(event) => setBurnAmount(event.target.value)} inputMode="numeric" />
          <small>Minimum now: {formatNumber(minimumBurn)} VOID. Burn more to set a harder record.</small>
        </label>
        <label>
          <span>NEW IMAGE</span>
          <input name="image" type="file" required accept="image/png,image/jpeg,image/gif" />
          <small>Decoded PNG, JPEG, or GIF. 2 MB / 2048 px maximum.</small>
        </label>
      </div>
      <label className="burn-warning">
        <input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)} />
        <span><strong>THE BURN CANNOT BE REFUNDED.</strong> Rejection, a failed submission, or another wallet setting a higher record does not restore your tokens.</span>
      </label>
      <div className={`terminal-status phase-${phase}`} aria-live="polite"><span />{message}</div>
      <button className="primary-action" type="submit" disabled={Boolean(disabledReason) || phase === "burning" || phase === "confirming" || phase === "preparing" || phase === "signing"} title={disabledReason ?? undefined}>
        {contractAddress ? "BEAT THE RECORD + SUBMIT" : "MAINNET DEPLOYMENT REQUIRED"}
      </button>
    </form>
  );
}

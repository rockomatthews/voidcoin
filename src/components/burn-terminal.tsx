"use client";

import { useEffect, useState, type FormEvent } from "react";
import { formatUnits } from "viem";
import { useAccount, useChainId, usePublicClient, useSignMessage, useSwitchChain, useWriteContract } from "wagmi";
import { WalletButton } from "@/components/wallet-button";
import { configuredChainId, configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { INITIAL_BURN_REQUIREMENT, MAX_STRATEGIC_PREMIUM, TAKEOVER_INCREMENT, TAKEOVER_INCREASE_PERCENT, formatNumber, nextTakeoverRequirement } from "@/lib/site";

type Phase = "idle" | "signing" | "preparing" | "burning" | "confirming" | "complete" | "error";
type PendingAuthorization = { id: string; wallet: string; commitment: `0x${string}`; proposedName: string; proposedSymbol: string };

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
  const [requiredBurn, setRequiredBurn] = useState(INITIAL_BURN_REQUIREMENT);
  const [maximumBurn, setMaximumBurn] = useState(INITIAL_BURN_REQUIREMENT + MAX_STRATEGIC_PREMIUM);
  const [tokenSymbol, setTokenSymbol] = useState("VOID");
  const [burnAmount, setBurnAmount] = useState(String(INITIAL_BURN_REQUIREMENT));
  const [balanceState, setBalanceState] = useState<{ wallet: string; value: number } | null>(null);
  const [ownsActiveSlot, setOwnsActiveSlot] = useState(false);
  const [pendingAuthorization, setPendingAuthorization] = useState<PendingAuthorization | null>(null);

  useEffect(() => {
    const controller = new AbortController();
    fetch("/api/state", { signal: controller.signal })
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("state unavailable")))
      .then((state: { symbol?: string; nextBurnAmount?: number; maximumBurnAmount?: number; activeSlot?: { burner: string } | null }) => {
        const nextMinimum = state.nextBurnAmount ?? INITIAL_BURN_REQUIREMENT;
        if (state.symbol) setTokenSymbol(state.symbol);
        setRequiredBurn(nextMinimum);
        setMaximumBurn(state.maximumBurnAmount ?? nextMinimum + MAX_STRATEGIC_PREMIUM);
        setBurnAmount(String(nextMinimum));
        setOwnsActiveSlot(Boolean(address && state.activeSlot?.burner.toLowerCase() === address.toLowerCase()));
      })
      .catch(() => undefined);
    return () => controller.abort();
  }, [address]);

  useEffect(() => {
    const controller = new AbortController();
    const loadIdentity = () => fetch("/api/state", { signal: controller.signal })
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("state unavailable")))
      .then((state: { symbol?: string }) => { if (state.symbol) setTokenSymbol(state.symbol); })
      .catch(() => undefined);
    void loadIdentity();
    const interval = window.setInterval(loadIdentity, 10_000);
    return () => { controller.abort(); window.clearInterval(interval); };
  }, []);

  useEffect(() => {
    if (!address) return;
    const controller = new AbortController();
    fetch(`/api/requests?wallet=${encodeURIComponent(address)}`, { signal: controller.signal })
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("requests unavailable")))
      .then((result: { requests?: Array<{ id: string; status: string; commitment: `0x${string}`; metadataURI: string | null; proposedName: string; proposedSymbol: string }> }) => {
        const pending = result.requests?.find((item) => item.status === "changes_requested" && item.metadataURI);
        setPendingAuthorization(pending ? { id: pending.id, wallet: address, commitment: pending.commitment, proposedName: pending.proposedName, proposedSymbol: pending.proposedSymbol } : null);
      })
      .catch(() => undefined);
    return () => controller.abort();
  }, [address]);

  useEffect(() => {
    if (!address || !contractAddress || !publicClient) return;
    let cancelled = false;
    publicClient.readContract({ address: contractAddress, abi: voidCoinAbi, functionName: "balanceOf", args: [address] })
      .then((value) => { if (!cancelled) setBalanceState({ wallet: address, value: Number(formatUnits(value, 18)) }); })
      .catch(() => undefined);
    return () => { cancelled = true; };
  }, [address, contractAddress, publicClient]);

  const balance = address && balanceState?.wallet.toLowerCase() === address.toLowerCase() ? balanceState.value : null;
  const authorization = address && pendingAuthorization?.wallet.toLowerCase() === address.toLowerCase() ? pendingAuthorization : null;
  const burnAmountNumber = /^\d+$/.test(burnAmount) ? Number(burnAmount) : Number.NaN;

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
      setMessage("Sanitizing the private image and binding the proposal to this burn level.");
      values.set("wallet", address);
      values.set("message", challenge.message);
      values.set("challengeToken", challenge.token);
      values.set("signature", signature);
      values.set("burnAmount", burnAmount);
      const requestResponse = await fetch("/api/requests", { method: "POST", body: values });
      const prepared = await requestResponse.json();
      if (!requestResponse.ok) throw new Error(prepared.error ?? "Could not prepare proposal");

      setPhase("burning");
      const isReplacement = prepared.mode === "replace";
      const burnAmountWei = BigInt(prepared.burnAmount);
      setMessage(isReplacement ? "Confirm the replacement proposal. No additional burn is required." : `Confirm the permanent burn of ${formatNumber(Number(burnAmountWei / 10n ** 18n))} ${tokenSymbol} in your wallet.`);
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
      setMessage(isReplacement ? "Replacement verified. The moderator has the new private submission." : "Burn verified. The moderator has been notified. A higher burn can take control before approval.");
      formElement.reset();
      if (!isReplacement) {
        const spent = Number(burnAmountWei / 10n ** 18n);
        const nextMinimum = nextTakeoverRequirement(spent);
        setRequiredBurn(nextMinimum);
        setMaximumBurn(nextMinimum + MAX_STRATEGIC_PREMIUM);
        setBurnAmount(String(nextMinimum));
        setBalanceState((current) => current === null ? null : { ...current, value: Math.max(0, current.value - spent) });
      }
      setAccepted(false);
    } catch (error) {
      setPhase("error");
      setMessage(error instanceof Error ? error.message : "The rename request could not be completed");
    }
  }

  async function authorizeApprovedMetadata() {
    if (!authorization || !contractAddress || !publicClient) return;
    try {
      if (chainId !== targetChainId) await switchChainAsync({ chainId: targetChainId });
      setPhase("burning");
      setMessage("Authorize the moderator-approved IPFS metadata. This does not burn additional VOID.");
      const transactionHash = await writeContractAsync({ address: contractAddress, abi: voidCoinAbi, functionName: "replaceCommitment", args: [authorization.commitment], chainId: targetChainId });
      setPhase("confirming");
      await publicClient.waitForTransactionReceipt({ hash: transactionHash });
      const response = await fetch(`/api/requests/${authorization.id}/confirm`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ transactionHash, mode: "replace" }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Final metadata authorization could not be verified");
      setPendingAuthorization(null);
      setPhase("complete");
      setMessage("Final metadata authorized. The moderator can now prepare the Safe approval.");
    } catch (error) {
      setPhase("error");
      setMessage(error instanceof Error ? error.message : "Final metadata authorization failed");
    }
  }

  const disabledReason = !contractAddress
    ? "The Base Mainnet contract has not been deployed yet."
    : !isConnected
      ? "Connect a wallet to enter the chamber."
      : !ownsActiveSlot && (!Number.isSafeInteger(burnAmountNumber) || burnAmountNumber < requiredBurn)
        ? `Set a whole-number burn of at least ${formatNumber(requiredBurn)} ${tokenSymbol}.`
      : !ownsActiveSlot && burnAmountNumber > maximumBurn
        ? `This record can be at most ${formatNumber(maximumBurn)} ${tokenSymbol}.`
      : balance !== null && balance < burnAmountNumber && !ownsActiveSlot
        ? `You need ${formatNumber(burnAmountNumber)} ${tokenSymbol} to submit this change.`
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
        <span className="terminal-code">NEXT BURN / {formatNumber(requiredBurn)} {tokenSymbol}</span>
      </div>
      <div className="wallet-access">
        <div><span>YOUR {tokenSymbol} BALANCE</span><strong>{isConnected ? balance === null ? "LOADING…" : formatNumber(balance) : "CONNECT TO VIEW"}</strong><small>{ownsActiveSlot ? "YOU CONTROL THE ACTIVE PROPOSAL" : `${formatNumber(requiredBurn)} ${tokenSymbol} REQUIRED`}</small></div>
        <WalletButton />
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
          <span>YOUR RECORD BURN</span>
          <input name="burnAmountDisplay" type="number" min={requiredBurn} max={maximumBurn} step="1" inputMode="numeric" value={burnAmount} onChange={(event) => setBurnAmount(event.target.value)} disabled={ownsActiveSlot} required={!ownsActiveSlot} />
          <small>The next record must clear both +{formatNumber(TAKEOVER_INCREMENT)} {tokenSymbol} and +{TAKEOVER_INCREASE_PERCENT}%. The larger rule wins. You may add up to {formatNumber(MAX_STRATEGIC_PREMIUM)} extra.</small>
        </label>
        <label>
          <span>NEW IMAGE</span>
          <input name="image" type="file" required accept="image/png,image/jpeg,image/gif" />
          <small>Decoded PNG, JPEG, or GIF. 2 MB / 2048 px maximum.</small>
        </label>
      </div>
      <label className="burn-warning">
        <input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)} />
        <span><strong>THE BURN CANNOT BE REFUNDED.</strong> Rejection, a failed submission, or another wallet setting the next higher burn does not restore your tokens.</span>
      </label>
      <div className={`terminal-status phase-${phase}`} aria-live="polite"><span />{message}</div>
      {authorization ? <button className="primary-action" type="button" onClick={authorizeApprovedMetadata} disabled={phase === "burning" || phase === "confirming"}>AUTHORIZE APPROVED {authorization.proposedName} / ${authorization.proposedSymbol}</button> : null}
      <button className="primary-action" type="submit" disabled={Boolean(disabledReason) || phase === "burning" || phase === "confirming" || phase === "preparing" || phase === "signing"} title={disabledReason ?? undefined}>
        {ownsActiveSlot ? "SUBMIT REPLACEMENT" : `BURN ${Number.isFinite(burnAmountNumber) ? formatNumber(burnAmountNumber) : "—"} ${tokenSymbol} + SUBMIT`}
      </button>
    </form>
  );
}

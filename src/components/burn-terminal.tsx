"use client";

import { useEffect, useState, type FormEvent } from "react";
import { formatUnits } from "viem";
import { useAccount, useChainId, usePublicClient, useSignMessage, useSwitchChain, useWriteContract } from "wagmi";
import { WalletButton } from "@/components/wallet-button";
import { configuredChainId, configuredControllerAddress, configuredTokenAddress, voidSkinControllerAbi, voidTokenAbi } from "@/lib/contract";
import { INITIAL_BURN_REQUIREMENT, MAX_STRATEGIC_PREMIUM, TAKEOVER_INCREMENT, TAKEOVER_INCREASE_PERCENT, formatNumber } from "@/lib/site";

type Phase = "idle" | "signing" | "preparing" | "burning" | "confirming" | "complete" | "error";
type PendingAuthorization = { id: string; wallet: string; burnId: string; burnAmount: string; commitment: `0x${string}`; submissionMode: "burn" | "replace"; proposedName: string; proposedSymbol: string };

function storedRequestIds() {
  try {
    const value = JSON.parse(window.localStorage.getItem("voidcoin-request-ids") ?? "[]");
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string" && /^[0-9a-f-]{36}$/i.test(item)).slice(0, 10) : [];
  } catch {
    return [];
  }
}

export function BurnTerminal() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const targetChainId = configuredChainId();
  const tokenAddress = configuredTokenAddress();
  const controllerAddress = configuredControllerAddress();
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
      .then((state: { symbol?: string; immutableSymbol?: string; nextBurnAmount?: number; maximumBurnAmount?: number; activeSlot?: { burner: string } | null }) => {
        const nextMinimum = state.nextBurnAmount ?? INITIAL_BURN_REQUIREMENT;
        if (state.immutableSymbol ?? state.symbol) setTokenSymbol(state.immutableSymbol ?? state.symbol!);
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
      .then((state: { symbol?: string; immutableSymbol?: string }) => {
        if (state.immutableSymbol ?? state.symbol) setTokenSymbol(state.immutableSymbol ?? state.symbol!);
      })
      .catch(() => undefined);
    void loadIdentity();
    const interval = window.setInterval(loadIdentity, 10_000);
    return () => { controller.abort(); window.clearInterval(interval); };
  }, []);

  useEffect(() => {
    if (!address) return;
    const controller = new AbortController();
    const load = () => {
      const ids = storedRequestIds();
      if (ids.length === 0) return Promise.resolve();
      return fetch(`/api/requests?wallet=${encodeURIComponent(address)}&ids=${encodeURIComponent(ids.join(","))}`, { signal: controller.signal })
      .then((response) => response.ok ? response.json() : Promise.reject(new Error("requests unavailable")))
      .then((result: { requests?: Array<{ id: string; status: string; submissionMode: "burn" | "replace"; burnId: string; burnAmount: string; commitment: `0x${string}` | null; metadataURI: string | null; proposedName: string; proposedSymbol: string }> }) => {
        const pending = result.requests?.find((item) => item.status === "awaiting_burn" && item.metadataURI && item.commitment);
        setPendingAuthorization(pending?.commitment ? { id: pending.id, wallet: address, burnId: pending.burnId, burnAmount: pending.burnAmount, commitment: pending.commitment, submissionMode: pending.submissionMode, proposedName: pending.proposedName, proposedSymbol: pending.proposedSymbol } : null);
      })
      .catch(() => undefined);
    };
    void load();
    const interval = window.setInterval(load, 10_000);
    return () => { controller.abort(); window.clearInterval(interval); };
  }, [address]);

  useEffect(() => {
    if (!address || !tokenAddress || !publicClient) return;
    let cancelled = false;
    publicClient.readContract({ address: tokenAddress, abi: voidTokenAbi, functionName: "balanceOf", args: [address] })
      .then((value) => { if (!cancelled) setBalanceState({ wallet: address, value: Number(formatUnits(value, 18)) }); })
      .catch(() => undefined);
    return () => { cancelled = true; };
  }, [address, tokenAddress, publicClient]);

  const balance = address && balanceState?.wallet.toLowerCase() === address.toLowerCase() ? balanceState.value : null;
  const authorization = address && pendingAuthorization?.wallet.toLowerCase() === address.toLowerCase() ? pendingAuthorization : null;
  const burnAmountNumber = /^\d+$/.test(burnAmount) ? Number(burnAmount) : Number.NaN;

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!address || !tokenAddress || !controllerAddress || !publicClient) return;
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

      setPhase("complete");
      const stored = storedRequestIds();
      const nextIds = [...new Set([prepared.requestId, ...stored])].slice(0, 10);
      window.localStorage.setItem("voidcoin-request-ids", JSON.stringify(nextIds));
      setMessage("Proposal stored privately for moderation. No approval or burn has occurred. When the final IPFS metadata is approved and pinned, this page will offer the exact executable commitment.");
      formElement.reset();
      setAccepted(false);
    } catch (error) {
      setPhase("error");
      setMessage(error instanceof Error ? error.message : "The rename request could not be completed");
    }
  }

  async function executeApprovedProposal() {
    if (!authorization || !controllerAddress || !publicClient) return;
    try {
      if (chainId !== targetChainId) await switchChainAsync({ chainId: targetChainId });
      setPhase("burning");
      const burnAmountWei = BigInt(authorization.burnAmount);
      if (authorization.submissionMode === "burn") {
        const allowance = await publicClient.readContract({ address: tokenAddress!, abi: voidTokenAbi, functionName: "allowance", args: [address!, controllerAddress] });
        if (allowance < burnAmountWei) {
          setMessage(`Approve exactly ${formatNumber(Number(burnAmountWei / 10n ** 18n))} ${tokenSymbol}. The final metadata is already pinned; approval alone does not burn.`);
          const approvalHash = await writeContractAsync({ address: tokenAddress!, abi: voidTokenAbi, functionName: "approve", args: [controllerAddress, burnAmountWei], chainId: targetChainId });
          const approvalReceipt = await publicClient.waitForTransactionReceipt({ hash: approvalHash });
          if (approvalReceipt.status !== "success") throw new Error("Token approval reverted on the configured chain");
        }
        setMessage(`Confirm the permanent token burn. The final metadata is already approved and pinned. The Safe must finalize within 72 hours.`);
      } else {
        setMessage("Confirm the pre-approved replacement commitment. No additional burn is required.");
      }
      const transactionHash = authorization.submissionMode === "replace"
        ? await writeContractAsync({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "replaceCommitment", args: [BigInt(authorization.burnId), authorization.commitment], chainId: targetChainId })
        : await writeContractAsync({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "burnForRename", args: [BigInt(authorization.burnId), burnAmountWei, authorization.commitment], chainId: targetChainId });
      setPhase("confirming");
      const receipt = await publicClient.waitForTransactionReceipt({ hash: transactionHash });
      if (receipt.status !== "success") throw new Error("The approved commitment reverted on the configured chain");
      const response = await fetch(`/api/requests/${authorization.id}/confirm`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ transactionHash, mode: authorization.submissionMode }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Final metadata authorization could not be verified");
      setPendingAuthorization(null);
      setPhase("complete");
      setMessage("Approved commitment verified. The moderator can now prepare the Safe batch; the onchain window closes 72 hours after this transaction.");
    } catch (error) {
      setPhase("error");
      setMessage(error instanceof Error ? error.message : "Approved commitment execution failed");
    }
  }

  const disabledReason = !tokenAddress || !controllerAddress
    ? "The token and transformation controller are not active yet."
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
          <span>NEW DISPLAY NAME — SITE/PROFILE ONLY</span>
          <input name="name" required maxLength={15} pattern="[A-Za-z0-9]+( [A-Za-z0-9]+)*" placeholder="NIGHT SHIFT" autoComplete="off" />
          <small>1–15 letters or numbers, single spaces only.</small>
        </label>
        <label>
          <span>NEW DISPLAY TICKER — SITE/PROFILE ONLY</span>
          <div className="ticker-input"><b>$</b><input name="symbol" required maxLength={10} pattern="[A-Za-z0-9]+" placeholder="NIGHT" autoComplete="off" /></div>
          <small>This does not change the token ticker shown by wallets or exchanges.</small>
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
        <span><strong>SUBMISSION DOES NOT BURN.</strong> If moderation approves and pins the final metadata, you will review a separate permanent burn transaction. Wallets and exchanges always show the immutable token as VOIDCOIN (VOID); only the site/profile display skin changes. Once executed, the burn cannot be refunded. The Safe has 72 hours to finalize it and can permanently end the contest only while paused with no active slot.</span>
      </label>
      <div className={`terminal-status phase-${phase}`} aria-live="polite"><span />{message}</div>
      {authorization ? <button className="primary-action" type="button" onClick={executeApprovedProposal} disabled={phase === "burning" || phase === "confirming"}>{authorization.submissionMode === "burn" ? "BURN FOR" : "AUTHORIZE"} APPROVED {authorization.proposedName} / ${authorization.proposedSymbol}</button> : null}
      <button className="primary-action" type="submit" disabled={Boolean(disabledReason) || phase === "burning" || phase === "confirming" || phase === "preparing" || phase === "signing"} title={disabledReason ?? undefined}>
        SUBMIT FOR MODERATION — NO BURN
      </button>
    </form>
  );
}

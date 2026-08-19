"use client";

import Link from "next/link";
import Image from "next/image";
import { useState } from "react";

interface RequestRow {
  id: string;
  burnId: string;
  burnAmount: string;
  wallet: string;
  proposedName: string;
  proposedSymbol: string;
  status: string;
  transactionHash: string | null;
  moderatorNote: string | null;
  safeCalldata: string | null;
  history: Array<{ name: string; symbol: string; createdAt: string }>;
}

export function AdminPanel({ initialRequests }: { initialRequests: RequestRow[] }) {
  const [requests, setRequests] = useState(initialRequests);
  const [output, setOutput] = useState("Choose a pending request to review its image, submission history, and Safe approval payload.");

  async function act(id: string, action: "request_changes" | "approve") {
    const note = action === "request_changes" ? window.prompt("Private moderation note for the burner:", "Please submit a non-discriminatory replacement.") ?? "" : undefined;
    const response = await fetch(`/api/admin/requests/${id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action, note }) });
    const result = await response.json();
    if (!response.ok) return setOutput(result.error ?? "Action failed");
    if (result.safeTransactions) {
      const rendered = result.safeTransactions.map((transaction: { description: string; to: string; data: string }, index: number) => `${index + 1}. ${transaction.description}\nTO: ${transaction.to}\nVALUE: 0\nDATA: ${transaction.data}`).join("\n\n");
      setOutput(`SAFE BATCH READY — EXECUTE IN ORDER\n${rendered}`);
      await navigator.clipboard?.writeText(rendered).catch(() => undefined);
    } else if (result.requiresBurnerAuthorization) {
      setOutput("CONTENT APPROVED AND PUBLISHED\nThe burner must now authorize the final IPFS metadata commitment. This requires no additional burn. Prepare the Safe batch after that transaction confirms.");
    } else {
      setOutput("Changes requested. The record holder can replace the private proposal without another burn unless a higher record takes control.");
    }
    setRequests((current) => current.map((item) => item.id === id ? { ...item, status: result.safeTransactions ? "ready_for_safe" : "changes_requested" } : item));
  }

  return (
    <div className="admin-panel">
      <header>
        <div><span className="eyebrow">SAFE-GATED CONTROL ROOM</span><h1>IDENTITY REVIEW</h1></div>
        <Link href="/">PUBLIC SITE ↗</Link>
      </header>
      <div className="review-grid">
        {requests.length === 0 ? <div className="empty-review">No identity requests yet. The first confirmed Base Mainnet record burn will appear here automatically.</div> : requests.map((item) => (
          <article className="review-card" key={item.id}>
            <div className="review-meta"><span>BURN / {item.burnId}</span><span>{item.status.replaceAll("_", " ")}</span></div>
            <Image className="review-image" src={`/api/admin/requests/${item.id}/image`} alt={`Private proposed artwork for ${item.proposedName}`} width={640} height={640} unoptimized />
            <h2>{item.proposedName}</h2>
            <strong>${item.proposedSymbol}</strong>
            <dl><div><dt>Wallet</dt><dd>{item.wallet}</dd></div><div><dt>Record</dt><dd>{(Number(BigInt(item.burnAmount) / 10n ** 18n)).toLocaleString()} VOID</dd></div></dl>
            <div className="review-actions"><button onClick={() => act(item.id, "request_changes")}>REQUEST CHANGES</button><button className="approve" onClick={() => act(item.id, "approve")}>PREPARE SAFE APPROVAL</button></div>
            <details className="submission-history"><summary>SUBMISSION HISTORY / {item.history.length}</summary>{item.history.map((entry) => <p key={`${entry.createdAt}-${entry.name}`}><span>{entry.createdAt.replace("T", " ").slice(0, 19)} UTC</span>{entry.name} / ${entry.symbol}</p>)}</details>
          </article>
        ))}
      </div>
      <pre className="safe-output">{output}</pre>
    </div>
  );
}

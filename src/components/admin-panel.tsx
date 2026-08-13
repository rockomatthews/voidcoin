"use client";

import Link from "next/link";
import Image from "next/image";
import { useState } from "react";

interface RequestRow {
  id: string;
  burnId: string;
  wallet: string;
  proposedName: string;
  proposedSymbol: string;
  status: string;
  transactionHash: string | null;
  expiresAt: string | null;
  moderatorNote: string | null;
  safeCalldata: string | null;
  history: Array<{ name: string; symbol: string; createdAt: string }>;
}

export function AdminPanel({ initialRequests }: { initialRequests: RequestRow[] }) {
  const [requests, setRequests] = useState(initialRequests);
  const [output, setOutput] = useState("Select a review action. Approval publishes the image to IPFS, then prepares—but does not execute—the Safe transaction.");

  async function act(id: string, action: "request_changes" | "approve") {
    const note = action === "request_changes" ? window.prompt("Private moderation note for the burner:", "Please submit a non-discriminatory replacement.") ?? "" : undefined;
    const response = await fetch(`/api/admin/requests/${id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ action, note }) });
    const result = await response.json();
    if (!response.ok) return setOutput(result.error ?? "Action failed");
    if (result.safeTransaction) {
      setOutput(`SAFE TRANSACTION READY\nTO: ${result.safeTransaction.to}\nVALUE: 0\nDATA: ${result.safeTransaction.data}`);
      await navigator.clipboard?.writeText(result.safeTransaction.data).catch(() => undefined);
    } else {
      setOutput("Changes requested. The active burn right remains valid until its original expiry.");
    }
    setRequests((current) => current.map((item) => item.id === id ? { ...item, status: action === "approve" ? "ready_for_safe" : "changes_requested" } : item));
  }

  return (
    <div className="admin-panel">
      <header>
        <div><span className="eyebrow">SAFE-GATED CONTROL ROOM</span><h1>IDENTITY REVIEW</h1></div>
        <Link href="/">PUBLIC SITE ↗</Link>
      </header>
      <div className="review-grid">
        {requests.length === 0 ? <div className="empty-review">No live requests. Configure Neon and complete a Sepolia burn to populate this chamber.</div> : requests.map((item) => (
          <article className="review-card" key={item.id}>
            <div className="review-meta"><span>BURN / {item.burnId}</span><span>{item.status.replaceAll("_", " ")}</span></div>
            <Image className="review-image" src={`/api/admin/requests/${item.id}/image`} alt={`Private proposed artwork for ${item.proposedName}`} width={640} height={640} unoptimized />
            <h2>{item.proposedName}</h2>
            <strong>${item.proposedSymbol}</strong>
            <dl><div><dt>Wallet</dt><dd>{item.wallet}</dd></div><div><dt>Expires</dt><dd>{item.expiresAt ?? "Awaiting burn"}</dd></div></dl>
            <div className="review-actions"><button onClick={() => act(item.id, "request_changes")}>REQUEST CHANGES</button><button className="approve" onClick={() => act(item.id, "approve")}>PREPARE SAFE APPROVAL</button></div>
            <details className="submission-history"><summary>SUBMISSION HISTORY / {item.history.length}</summary>{item.history.map((entry) => <p key={`${entry.createdAt}-${entry.name}`}><span>{entry.createdAt.replace("T", " ").slice(0, 19)} UTC</span>{entry.name} / ${entry.symbol}</p>)}</details>
          </article>
        ))}
      </div>
      <pre className="safe-output">{output}</pre>
    </div>
  );
}

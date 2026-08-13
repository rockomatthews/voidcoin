"use client";

import { useEffect, useState } from "react";
import { formatNumber, shortAddress } from "@/lib/site";

interface StateData {
  configured: boolean;
  name: string;
  symbol: string;
  originalSupply: number;
  currentSupply: number;
  burned: number;
  burnAmount: number;
  renamePaused: boolean;
  message?: string;
  activeSlot: null | { burner: string; expiresAt: number; burnId: string };
}

const preview: StateData = { configured: false, name: "VOIDCOIN", symbol: "VOID", originalSupply: 1_000_000_000, currentSupply: 1_000_000_000, burned: 0, burnAmount: 1_000_000, renamePaused: true, activeSlot: null, message: "Base Sepolia deployment pending" };

export function LiveState() {
  const [state, setState] = useState<StateData>(preview);

  useEffect(() => {
    const controller = new AbortController();
    fetch("/api/state", { signal: controller.signal })
      .then((response) => (response.ok ? response.json() : Promise.reject(new Error("state unavailable"))))
      .then(setState)
      .catch(() => undefined);
    return () => controller.abort();
  }, []);

  const status = state.renamePaused ? "LOCKED" : state.activeSlot ? "UNDER REVIEW" : "OPEN";
  return (
    <>
      <div className="identity-readout">
        <span className="eyebrow">CURRENT APPROVED SKIN</span>
        <h2>{state.name}</h2>
        <div className="ticker-chip">${state.symbol}</div>
        <p>{state.configured ? "Canonical contract state on Base." : state.message}</p>
      </div>
      <div className={`status-chamber status-${status.toLowerCase().replace(" ", "-")}`}>
        <div>
          <span className="eyebrow">RENAME CHAMBER</span>
          <strong>{status}</strong>
        </div>
        <span className="status-orb" />
        <p>{state.activeSlot ? `Burn ${state.activeSlot.burnId} · ${shortAddress(state.activeSlot.burner)}` : state.renamePaused ? "Entry remains gated until testnet verification is complete." : "One exact burn opens the next identity slot."}</p>
      </div>
      <div className="instrument-grid">
        <article className="instrument">
          <span>DESTROYED</span>
          <strong>{formatNumber(state.burned)}</strong>
          <small>{((state.burned / state.originalSupply) * 100).toFixed(3)}% OF GENESIS</small>
        </article>
        <article className="instrument">
          <span>CIRCULATING</span>
          <strong>{formatNumber(state.currentSupply)}</strong>
          <small>NO NEW MINTING</small>
        </article>
        <article className="instrument">
          <span>IDENTITY COST</span>
          <strong>{formatNumber(state.burnAmount)}</strong>
          <small>PERMANENT BURN</small>
        </article>
      </div>
    </>
  );
}

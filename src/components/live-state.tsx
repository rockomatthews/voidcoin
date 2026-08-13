"use client";

import { useEffect, useState } from "react";
import { formatNumber, shortAddress } from "@/lib/site";

interface StateData {
  configured: boolean;
  recordBurn: number;
  nextBurnAmount: number;
  recordBurner: string | null;
}

const preview: StateData = {
  configured: false,
  recordBurn: 0,
  nextBurnAmount: 1_000_000,
  recordBurner: null,
};

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

  return (
    <div className="record-strip" aria-live="polite">
      <div><span>CURRENT RECORD</span><strong>{formatNumber(state.recordBurn)} VOID</strong></div>
      <div className="record-next"><span>BURN TO TAKE CONTROL</span><strong>{formatNumber(state.nextBurnAmount)} VOID</strong></div>
      <div><span>RECORD HOLDER</span><strong>{state.recordBurner ? shortAddress(state.recordBurner) : "UNCLAIMED"}</strong></div>
    </div>
  );
}

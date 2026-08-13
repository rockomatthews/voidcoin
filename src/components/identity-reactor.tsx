"use client";

import { useRef, type PointerEvent } from "react";

export function IdentityReactor() {
  const reactor = useRef<HTMLDivElement>(null);

  function handlePointerMove(event: PointerEvent<HTMLDivElement>) {
    const element = reactor.current;
    if (!element || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const rect = element.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - 0.5;
    const y = (event.clientY - rect.top) / rect.height - 0.5;
    element.style.setProperty("--reactor-rotate-y", `${x * 11}deg`);
    element.style.setProperty("--reactor-rotate-x", `${y * -8}deg`);
  }

  function reset() {
    reactor.current?.style.removeProperty("--reactor-rotate-y");
    reactor.current?.style.removeProperty("--reactor-rotate-x");
  }

  return (
    <div className="reactor-shell" ref={reactor} onPointerMove={handlePointerMove} onPointerLeave={reset} aria-label="VOIDCOIN identity reactor visualization">
      <div className="reactor-grid" />
      <div className="reactor-ring ring-one" />
      <div className="reactor-ring ring-two" />
      <div className="reactor-beam" />
      <div className="token-monolith">
        <div className="token-face token-front">
          <span className="token-kicker">SKIN / 000</span>
          <strong>VOID</strong>
          <span className="token-supply">1B GENESIS SUPPLY</span>
        </div>
        <div className="token-face token-side" />
        <div className="token-face token-top" />
      </div>
      <div className="reactor-warning">IDENTITY MUTABLE</div>
      <div className="reactor-axis axis-x" />
      <div className="reactor-axis axis-y" />
    </div>
  );
}

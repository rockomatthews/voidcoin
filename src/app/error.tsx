"use client";

export default function ErrorPage({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <main className="error-shell"><span className="eyebrow">SIGNAL INTERRUPTED</span><h1>THE VOID DID NOT ANSWER.</h1><p>A local subsystem failed without changing contract state.</p><button className="primary-action" onClick={reset}>RETRY SIGNAL</button></main>;
}

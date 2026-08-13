"use client";

import { useState, type FormEvent } from "react";

export function AdminLogin() {
  const [status, setStatus] = useState("Enter the allowlisted moderator email.");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const email = new FormData(event.currentTarget).get("email");
    const response = await fetch("/api/admin/auth/request", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email }) });
    const result = await response.json();
    if (!response.ok) return setStatus(result.error ?? "Sign-in could not be sent");
    if (result.previewUrl) return setStatus(`Local preview link: ${result.previewUrl}`);
    setStatus("If the address is authorized, a 15-minute sign-in link is on its way.");
  }

  return (
    <form className="admin-login" onSubmit={submit}>
      <span className="eyebrow">RESTRICTED MODERATION CHANNEL</span>
      <h1>IDENTITY REVIEW</h1>
      <p>{status}</p>
      <input name="email" type="email" required placeholder="moderator@example.com" autoComplete="email" />
      <button className="primary-action" type="submit">SEND SECURE LINK</button>
    </form>
  );
}

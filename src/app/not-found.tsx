import Link from "next/link";

export default function NotFound() {
  return <main className="error-shell"><span className="eyebrow">404 / LOST SIGNAL</span><h1>NOTHING LIVES HERE.</h1><Link className="primary-action" href="/">RETURN TO VOIDCOIN</Link></main>;
}

import type { Metadata, Viewport } from "next";
import { Providers } from "@/components/providers";
import { getSiteUrl } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(getSiteUrl()),
  title: "VOIDCOIN — Burn the old. Author the next.",
  description: "A Base-native token whose identity belongs to the wallet that sets the highest permanent burn record and passes community-safety review.",
  alternates: { canonical: "/" },
  applicationName: "VOIDCOIN",
  openGraph: {
    type: "website",
    url: "/",
    siteName: "VOIDCOIN",
    title: "VOIDCOIN — Burn the old. Author the next.",
    description: "Outburn the last holder. Propose the next onchain identity.",
    images: [{ url: "/og.png", width: 1731, height: 909, alt: "VOIDCOIN identity reactor" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "VOIDCOIN — Burn the old. Author the next.",
    description: "A competitive-burn, moderator-gated mutable token identity on Base.",
    images: ["/og.png"],
  },
  icons: { icon: "/icon.svg", apple: "/icon.svg" },
};

export const viewport: Viewport = { themeColor: "#07080a", colorScheme: "dark" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body><Providers>{children}</Providers></body>
    </html>
  );
}

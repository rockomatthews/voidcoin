import type { Metadata, Viewport } from "next";
import { Providers } from "@/components/providers";
import { getPublicClient } from "@/lib/chain";
import { configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { getSiteUrl } from "@/lib/site";
import { imageFromTokenURI } from "@/lib/token-metadata";
import "./globals.css";

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  let name = "VOIDCOIN";
  let symbol = "VOID";
  let image = "/voidcoin-logo.png";
  const address = configuredContractAddress();
  if (address) {
    try {
      const client = getPublicClient();
      const [liveName, liveSymbol, tokenURI] = await Promise.all([
        client.readContract({ address, abi: voidCoinAbi, functionName: "name" }),
        client.readContract({ address, abi: voidCoinAbi, functionName: "symbol" }),
        client.readContract({ address, abi: voidCoinAbi, functionName: "tokenURI" }),
      ]);
      name = liveName;
      symbol = liveSymbol;
      image = await imageFromTokenURI(tokenURI) ?? image;
    } catch {
      // A temporary RPC or IPFS failure must not prevent the permanent website shell from rendering.
    }
  }
  const title = `${name} ($${symbol}) — Try to control the coin that transforms`;
  const description = "A Base-native token whose identity belongs to the wallet that sets the highest permanent burn record and passes community-safety review.";
  return {
    metadataBase: new URL(getSiteUrl()),
    title,
    description,
    alternates: { canonical: "/" },
    applicationName: name,
    openGraph: {
      type: "website",
      url: "/",
      siteName: name,
      title,
      description: "Outburn the last holder. Propose the next onchain identity.",
      images: [{ url: image, alt: `${name} current token image` }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description: "A competitive-burn, moderator-gated mutable token identity on Base.",
      images: [image],
    },
    icons: { icon: image, apple: image },
  };
}

export const viewport: Viewport = { themeColor: "#07080a", colorScheme: "dark" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body><Providers>{children}</Providers></body>
    </html>
  );
}

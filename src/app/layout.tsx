import type { Metadata, Viewport } from "next";
import { Providers } from "@/components/providers";
import { getPublicClient } from "@/lib/chain";
import { configuredControllerAddress, configuredMarketVersion, configuredMetadataFunction, configuredTokenAddress, hoodSkinControllerAbi, voidTokenAbi } from "@/lib/contract";
import { getSiteUrl } from "@/lib/site";
import { imageFromTokenURI } from "@/lib/token-metadata";
import "./globals.css";

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  let name = "VOIDCOIN";
  let symbol = "VOID";
  let immutableName = "VOIDCOIN";
  let immutableSymbol = "VOID";
  let image = "/voidcoin-logo.png";
  const address = configuredTokenAddress();
  const metadataFunction = configuredMetadataFunction();
  const marketVersion = configuredMarketVersion();
  const controller = configuredControllerAddress();
  if (address) {
    try {
      const client = getPublicClient();
      const [liveName, liveSymbol, tokenURI] = await Promise.all([
        client.readContract({ address, abi: voidTokenAbi, functionName: "name" }),
        client.readContract({ address, abi: voidTokenAbi, functionName: "symbol" }),
        client.readContract({ address, abi: voidTokenAbi, functionName: metadataFunction }),
      ]);
      name = liveName;
      symbol = liveSymbol;
      immutableName = liveName;
      immutableSymbol = liveSymbol;
      image = await imageFromTokenURI(tokenURI) ?? image;
      if (marketVersion === "hood" && controller) {
        [name, symbol] = await Promise.all([
          client.readContract({ address: controller, abi: hoodSkinControllerAbi, functionName: "displayName" }),
          client.readContract({ address: controller, abi: hoodSkinControllerAbi, functionName: "displaySymbol" }),
        ]);
      }
    } catch {
      // A temporary RPC or IPFS failure must not prevent the permanent website shell from rendering.
    }
  }
  const title = marketVersion === "hood"
    ? `${name} ($${symbol}) · token ${immutableName} ($${immutableSymbol})`
    : `${name} ($${symbol}) — Try to control the coin that transforms`;
  const description = marketVersion === "hood"
    ? `A Robinhood Chain token launched through hood.dev and purchasable through Fomo. ${name} ($${symbol}) is its mutable display skin; wallets and exchanges always show ${immutableName} (${immutableSymbol}).`
    : "A Base-native token whose identity belongs to the wallet that sets the highest permanent burn record and passes community-safety review.";
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
      description,
      images: [{ url: image, alt: `${name} current token image` }],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
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

import { configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { getPublicClient } from "@/lib/chain";

interface TokenMetadata { image?: string }
interface ArchiveIdentity {
  burnId: string;
  name: string;
  symbol: string;
  image: string | null;
  burner: string;
  transactionHash: `0x${string}` | null;
}

function ipfsUrl(uri: string) {
  if (!uri.startsWith("ipfs://")) return null;
  const cid = uri.slice(7).replace(/^ipfs\//, "");
  return `${process.env.PINATA_GATEWAY ?? "https://gateway.pinata.cloud/ipfs"}/${cid}`;
}

async function imageFromMetadata(uri: string) {
  const url = ipfsUrl(uri);
  if (!url) return null;
  try {
    const response = await fetch(url, { next: { revalidate: 300 }, signal: AbortSignal.timeout(5_000) });
    if (!response.ok) return null;
    const metadata = await response.json() as TokenMetadata;
    return metadata.image ? ipfsUrl(metadata.image) : null;
  } catch {
    return null;
  }
}

export async function GET() {
  const address = configuredContractAddress();
  const deploymentBlock = process.env.NEXT_PUBLIC_VOIDCOIN_DEPLOYMENT_BLOCK;
  if (!address || !deploymentBlock) {
    return Response.json({ configured: false, identities: [{ burnId: "0", name: "VOIDCOIN", symbol: "VOID", image: "/voidcoin-logo.png", burner: "GENESIS", transactionHash: null }] });
  }

  try {
    const client = getPublicClient();
    const logs = await client.getContractEvents({ address, abi: voidCoinAbi, eventName: "SkinChanged", fromBlock: BigInt(deploymentBlock), toBlock: "latest" });
    const identities: ArchiveIdentity[] = await Promise.all(logs.toReversed().map(async (log) => ({
      burnId: log.args.burnId?.toString() ?? "",
      name: log.args.name ?? "",
      symbol: log.args.symbol ?? "",
      image: log.args.metadataURI ? await imageFromMetadata(log.args.metadataURI) : null,
      burner: log.args.burner ?? "",
      transactionHash: log.transactionHash,
    })));
    identities.push({ burnId: "0", name: "VOIDCOIN", symbol: "VOID", image: "/voidcoin-logo.png", burner: "GENESIS", transactionHash: null });
    return Response.json({ configured: true, identities }, { headers: { "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300" } });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Archive unavailable" }, { status: 502 });
  }
}

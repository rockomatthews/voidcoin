import { formatUnits } from "viem";
import { configuredControllerAddress, voidSkinControllerAbi } from "@/lib/contract";
import { getPublicClient } from "@/lib/chain";
import { imageFromTokenURI } from "@/lib/token-metadata";

interface ArchiveIdentity {
  burnId: string;
  name: string;
  symbol: string;
  image: string | null;
  burner: string;
  transactionHash: `0x${string}` | null;
  burnTransactionHash: `0x${string}` | null;
  burnAmount: number;
  timestamp: number | null;
}

export async function GET() {
  const address = configuredControllerAddress();
  const deploymentBlock = process.env.NEXT_PUBLIC_VOID_SKIN_CONTROLLER_DEPLOYMENT_BLOCK;
  if (!address || !deploymentBlock) {
    return Response.json({ configured: false, identities: [{ burnId: "0", name: "VOIDCOIN", symbol: "VOID", image: "/voidcoin-logo.png", burner: "GENESIS", transactionHash: null, burnTransactionHash: null, burnAmount: 0, timestamp: null }], burns: [] });
  }

  try {
    const client = getPublicClient();
    const fromBlock = BigInt(deploymentBlock);
    const [skinLogs, burnLogs] = await Promise.all([
      client.getContractEvents({ address, abi: voidSkinControllerAbi, eventName: "SkinChanged", fromBlock, toBlock: "latest" }),
      client.getContractEvents({ address, abi: voidSkinControllerAbi, eventName: "RenameBurned", fromBlock, toBlock: "latest" }),
    ]);
    const blockNumbers = [...new Set([...skinLogs, ...burnLogs].flatMap((log) => log.blockNumber === null ? [] : [log.blockNumber]))];
    const blocks = await Promise.all(blockNumbers.map((blockNumber) => client.getBlock({ blockNumber })));
    const timestamps = new Map(blocks.map((block) => [block.number.toString(), Number(block.timestamp)]));
    const burns = burnLogs.map((log) => ({
      burnId: log.args.burnId?.toString() ?? "",
      burner: log.args.burner ?? "",
      amount: Number(formatUnits(log.args.amount ?? 0n, 18)),
      transactionHash: log.transactionHash,
      timestamp: log.blockNumber === null ? null : timestamps.get(log.blockNumber.toString()) ?? null,
    }));
    const burnsById = new Map(burns.map((burn) => [burn.burnId, burn]));
    const identities: ArchiveIdentity[] = await Promise.all(skinLogs.toReversed().map(async (log) => {
      const burnId = log.args.burnId?.toString() ?? "";
      const burn = burnsById.get(burnId);
      return {
        burnId,
        name: log.args.name ?? "",
        symbol: log.args.symbol ?? "",
        image: log.args.metadataURI ? await imageFromTokenURI(log.args.metadataURI) : null,
        burner: log.args.burner ?? "",
        transactionHash: log.transactionHash,
        burnTransactionHash: burn?.transactionHash ?? null,
        burnAmount: burn?.amount ?? 0,
        timestamp: log.blockNumber === null ? null : timestamps.get(log.blockNumber.toString()) ?? null,
      };
    }));
    identities.push({ burnId: "0", name: "VOIDCOIN", symbol: "VOID", image: "/voidcoin-logo.png", burner: "GENESIS", transactionHash: null, burnTransactionHash: null, burnAmount: 0, timestamp: null });
    return Response.json({ configured: true, identities, burns }, { headers: { "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300" } });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Archive unavailable" }, { status: 502 });
  }
}

import { formatUnits } from "viem";
import { configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { getPublicClient } from "@/lib/chain";
import { BURN_AMOUNT, INITIAL_TOKEN_NAME, INITIAL_TOKEN_SYMBOL, ORIGINAL_SUPPLY } from "@/lib/site";

export async function GET() {
  const address = configuredContractAddress();
  if (!address) {
    return Response.json({ mode: "preview", configured: false, name: INITIAL_TOKEN_NAME, symbol: INITIAL_TOKEN_SYMBOL, originalSupply: ORIGINAL_SUPPLY, currentSupply: ORIGINAL_SUPPLY, burned: 0, burnAmount: BURN_AMOUNT, renamePaused: true, activeSlot: null, message: "Base Sepolia deployment pending" });
  }

  try {
    const client = getPublicClient();
    const [name, symbol, supply, burned, paused, slot, uri] = await Promise.all([
      client.readContract({ address, abi: voidCoinAbi, functionName: "name" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "symbol" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "totalSupply" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "destroyedSupply" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "renamePaused" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "activeSlot" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "tokenURI" }),
    ]);
    return Response.json({
      mode: "live",
      configured: true,
      address,
      name,
      symbol,
      tokenURI: uri,
      originalSupply: ORIGINAL_SUPPLY,
      currentSupply: Number(formatUnits(supply, 18)),
      burned: Number(formatUnits(burned, 18)),
      burnAmount: BURN_AMOUNT,
      renamePaused: paused,
      activeSlot: slot.burner === "0x0000000000000000000000000000000000000000" ? null : { burnId: slot.burnId.toString(), burner: slot.burner, commitment: slot.commitment, openedAt: Number(slot.openedAt), expiresAt: Number(slot.expiresAt) },
    });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Could not read Base state" }, { status: 502 });
  }
}

import { formatUnits } from "viem";
import { configuredContractAddress, voidCoinAbi } from "@/lib/contract";
import { getPublicClient } from "@/lib/chain";
import { BURN_INCREMENT, INITIAL_TOKEN_NAME, INITIAL_TOKEN_SYMBOL, ORIGINAL_SUPPLY } from "@/lib/site";

export async function GET() {
  const address = configuredContractAddress();
  if (!address) {
    return Response.json({ mode: "preview", configured: false, name: INITIAL_TOKEN_NAME, symbol: INITIAL_TOKEN_SYMBOL, originalSupply: ORIGINAL_SUPPLY, currentSupply: ORIGINAL_SUPPLY, burned: 0, recordBurn: 0, nextBurnAmount: BURN_INCREMENT, recordBurner: null, renamePaused: true, activeSlot: null, message: "Base Mainnet deployment pending" });
  }

  try {
    const client = getPublicClient();
    const [name, symbol, supply, burned, paused, slot, uri, record, nextRequirement, recordHolder] = await Promise.all([
      client.readContract({ address, abi: voidCoinAbi, functionName: "name" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "symbol" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "totalSupply" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "destroyedSupply" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "renamePaused" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "activeSlot" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "tokenURI" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "recordBurn" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "nextBurnRequirement" }),
      client.readContract({ address, abi: voidCoinAbi, functionName: "recordBurner" }),
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
      recordBurn: Number(formatUnits(record, 18)),
      nextBurnAmount: Number(formatUnits(nextRequirement, 18)),
      recordBurner: recordHolder === "0x0000000000000000000000000000000000000000" ? null : recordHolder,
      renamePaused: paused,
      activeSlot: slot.burner === "0x0000000000000000000000000000000000000000" ? null : { burnId: slot.burnId.toString(), burner: slot.burner, burnAmount: Number(formatUnits(slot.burnAmount, 18)), commitment: slot.commitment, openedAt: Number(slot.openedAt), lockedUntil: Number(slot.lockedUntil) },
    });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Could not read Base state" }, { status: 502 });
  }
}

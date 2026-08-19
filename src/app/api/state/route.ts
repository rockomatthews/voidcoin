import { formatUnits } from "viem";
import { configuredControllerAddress, configuredTokenAddress, voidSkinControllerAbi, zoraContentCoinAbi } from "@/lib/contract";
import { getPublicClient } from "@/lib/chain";
import { INITIAL_BURN_REQUIREMENT, INITIAL_TOKEN_NAME, INITIAL_TOKEN_SYMBOL, MAX_STRATEGIC_PREMIUM, ORIGINAL_SUPPLY } from "@/lib/site";
import { imageFromTokenURI } from "@/lib/token-metadata";

export async function GET() {
  const tokenAddress = configuredTokenAddress();
  const controllerAddress = configuredControllerAddress();
  if (!tokenAddress || !controllerAddress) {
    return Response.json({ mode: "preview", configured: false, name: INITIAL_TOKEN_NAME, symbol: INITIAL_TOKEN_SYMBOL, image: "/voidcoin-logo.png", tokenURI: null, originalSupply: ORIGINAL_SUPPLY, currentSupply: ORIGINAL_SUPPLY, burned: 0, recordBurn: 0, nextBurnAmount: INITIAL_BURN_REQUIREMENT, maximumBurnAmount: INITIAL_BURN_REQUIREMENT + MAX_STRATEGIC_PREMIUM, recordBurner: null, renamePaused: true, activeSlot: null, message: "Base Mainnet deployment pending" });
  }

  try {
    const client = getPublicClient();
    const [name, symbol, supply, burned, paused, slot, uri, record, nextRequirement, maximumBurn, recordHolder] = await Promise.all([
      client.readContract({ address: tokenAddress, abi: zoraContentCoinAbi, functionName: "name" }),
      client.readContract({ address: tokenAddress, abi: zoraContentCoinAbi, functionName: "symbol" }),
      client.readContract({ address: tokenAddress, abi: zoraContentCoinAbi, functionName: "totalSupply" }),
      client.readContract({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "destroyedSupply" }),
      client.readContract({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "renamePaused" }),
      client.readContract({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "activeSlot" }),
      client.readContract({ address: tokenAddress, abi: zoraContentCoinAbi, functionName: "tokenURI" }),
      client.readContract({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "recordBurn" }),
      client.readContract({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "nextBurnRequirement" }),
      client.readContract({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "maximumBurnAmount" }),
      client.readContract({ address: controllerAddress, abi: voidSkinControllerAbi, functionName: "recordBurner" }),
    ]);
    const image = await imageFromTokenURI(uri);
    return Response.json({
      mode: "live",
      configured: true,
      address: tokenAddress,
      tokenAddress,
      controllerAddress,
      name,
      symbol,
      tokenURI: uri,
      image,
      originalSupply: ORIGINAL_SUPPLY,
      currentSupply: Number(formatUnits(supply, 18)),
      burned: Number(formatUnits(burned, 18)),
      recordBurn: Number(formatUnits(record, 18)),
      nextBurnAmount: Number(formatUnits(nextRequirement, 18)),
      maximumBurnAmount: Number(formatUnits(maximumBurn, 18)),
      recordBurner: recordHolder === "0x0000000000000000000000000000000000000000" ? null : recordHolder,
      renamePaused: paused,
      activeSlot: slot.burner === "0x0000000000000000000000000000000000000000" ? null : { burnId: slot.burnId.toString(), burner: slot.burner, burnAmount: Number(formatUnits(slot.burnAmount, 18)), commitment: slot.commitment, openedAt: Number(slot.openedAt), lockedUntil: Number(slot.lockedUntil) },
    }, { headers: { "Cache-Control": "public, s-maxage=5, stale-while-revalidate=15" } });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Could not read Base state" }, { status: 502 });
  }
}

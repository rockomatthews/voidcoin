import { formatEther, formatUnits, parseEther } from "viem";
import { getPublicClient } from "@/lib/chain";
import { configuredCurveAddress, configuredContractAddress, voidBondingCurveAbi } from "@/lib/contract";
import { uniswapBuyUrl } from "@/lib/purchase";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const amount = new URL(request.url).searchParams.get("eth") ?? "0.11";
  let ethIn: bigint;
  try {
    ethIn = parseEther(amount);
  } catch {
    return Response.json({ error: "Enter a valid ETH amount." }, { status: 400 });
  }

  if (ethIn <= 0n) return Response.json({ error: "ETH amount must be greater than zero." }, { status: 400 });

  try {
    const client = getPublicClient();
    const curveAddress = configuredCurveAddress();
    const [maxBuy, ethReserve, graduationThreshold, graduated] = await Promise.all([
      client.readContract({ address: curveAddress, abi: voidBondingCurveAbi, functionName: "maxBuyAmount" }),
      client.readContract({ address: curveAddress, abi: voidBondingCurveAbi, functionName: "ethReserve" }),
      client.readContract({ address: curveAddress, abi: voidBondingCurveAbi, functionName: "graduationThreshold" }),
      client.readContract({ address: curveAddress, abi: voidBondingCurveAbi, functionName: "graduated" }),
    ]);

    if (ethIn > maxBuy) {
      return Response.json({ error: `Maximum purchase is ${formatEther(maxBuy)} ETH.`, maxBuyEth: formatEther(maxBuy) }, { status: 400 });
    }

    const tokensOut = graduated ? 0n : await client.readContract({ address: curveAddress, abi: voidBondingCurveAbi, functionName: "quoteBuy", args: [ethIn] });
    return Response.json({
      curveAddress,
      tokenAddress: configuredContractAddress(),
      graduated,
      ethReserve: formatEther(ethReserve),
      graduationThreshold: formatEther(graduationThreshold),
      progress: Math.min(100, Number(ethReserve * 10_000n / graduationThreshold) / 100),
      maxBuyEth: formatEther(maxBuy),
      tokensOut: formatUnits(tokensOut, 18),
      tokensOutWei: tokensOut.toString(),
      uniswapUrl: uniswapBuyUrl(),
    }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return Response.json({ error: "Could not read the live Base market. Try again in a moment." }, { status: 502 });
  }
}

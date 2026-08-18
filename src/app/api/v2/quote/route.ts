import { encodePacked, formatEther, formatUnits, parseEther } from "viem";
import { getPublicClient } from "@/lib/chain";
import {
  BASE_UNISWAP_V3_QUOTER_V2,
  BASE_USDC_ADDRESS,
  BASE_WETH_ADDRESS,
  VOID_USDC_POOL_FEE,
  WETH_USDC_POOL_FEE,
  configuredContractAddress,
  configuredMarketVersion,
  uniswapQuoterV2Abi,
} from "@/lib/contract";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  if (configuredMarketVersion() !== "v2") {
    return Response.json({ error: "VOIDCOIN V2 market is not configured yet." }, { status: 503 });
  }

  const amount = new URL(request.url).searchParams.get("eth") ?? "0.0005";
  let ethIn: bigint;
  try {
    ethIn = parseEther(amount);
  } catch {
    return Response.json({ error: "Enter a valid ETH amount." }, { status: 400 });
  }
  if (ethIn <= 0n) return Response.json({ error: "ETH amount must be greater than zero." }, { status: 400 });

  try {
    const token = configuredContractAddress();
    const path = encodePacked(
      ["address", "uint24", "address", "uint24", "address"],
      [BASE_WETH_ADDRESS, WETH_USDC_POOL_FEE, BASE_USDC_ADDRESS, VOID_USDC_POOL_FEE, token],
    );
    const { result } = await getPublicClient().simulateContract({
      address: BASE_UNISWAP_V3_QUOTER_V2,
      abi: uniswapQuoterV2Abi,
      functionName: "quoteExactInput",
      args: [path, ethIn],
    });
    const [tokensOut] = result;
    return Response.json({
      tokenAddress: token,
      ethIn: formatEther(ethIn),
      tokensOut: formatUnits(tokensOut, 18),
      tokensOutWei: tokensOut.toString(),
    }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return Response.json({ error: "Could not quote the live Base Uniswap market. Try again in a moment." }, { status: 502 });
  }
}

import { MAINNET_VOIDCOIN_ADDRESS } from "./contract";

export const BUY_SLIPPAGE_BPS = 100n;
export const BPS = 10_000n;

export function minimumTokensOut(quotedTokens: bigint) {
  return quotedTokens * (BPS - BUY_SLIPPAGE_BPS) / BPS;
}

export function uniswapBuyUrl() {
  return `https://app.uniswap.org/swap?chain=base&outputCurrency=${MAINNET_VOIDCOIN_ADDRESS}`;
}

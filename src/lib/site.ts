export const SITE_NAME = "VOIDCOIN";
export const INITIAL_TOKEN_NAME = "VOIDCOIN";
export const INITIAL_TOKEN_SYMBOL = "VOID";
export const ORIGINAL_SUPPLY = 1_000_000_000;
export const MINIMUM_BURN_INCREMENT = 1_000_000;

export function getSiteUrl() {
  return process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/$/, "") ?? "http://localhost:3000";
}

export function shortAddress(value: string) {
  return value.length > 12 ? `${value.slice(0, 6)}…${value.slice(-4)}` : value;
}

export function formatNumber(value: number) {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(value);
}

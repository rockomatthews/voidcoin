export const SITE_NAME = "VOIDCOIN";
export const CANONICAL_SITE_URL = "https://voidcoin.fun";
export const INITIAL_TOKEN_NAME = "VOIDCOIN";
export const INITIAL_TOKEN_SYMBOL = "VOID";
export const ORIGINAL_SUPPLY = 1_000_000_000;
export const INITIAL_BURN_REQUIREMENT = 1_000_000;
export const TAKEOVER_INCREMENT = 250_000;
export const TAKEOVER_INCREASE_PERCENT = 10;
export const MAX_STRATEGIC_PREMIUM = 2_000_000;

export function nextTakeoverRequirement(previous: number) {
  if (previous <= 0) return INITIAL_BURN_REQUIREMENT;
  const percentageIncrease = Math.floor((previous * (100 + TAKEOVER_INCREASE_PERCENT) + 99) / 100);
  return Math.max(previous + TAKEOVER_INCREMENT, percentageIncrease);
}

export function getSiteUrl() {
  return CANONICAL_SITE_URL;
}

export function shortAddress(value: string) {
  return value.length > 12 ? `${value.slice(0, 6)}…${value.slice(-4)}` : value;
}

export function formatNumber(value: number) {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(value);
}

// Store catalog shared by the store pages, the x402 route config, and the agent.
// All prices are integer cents.
export type PaymentMethod = "x402" | "card";

export type Item = {
  id: string;
  name: string;
  priceCents: number;
  method: PaymentMethod;
  // x402 items: the protected API path. Card items: the checkout page.
  path: string;
};

// The only place item prices are set. Everything else reads these.
export const MARKET_REPORT_PRICE_CENTS = 50;
export const PRICE_FEED_PRICE_CENTS = 100;
export const STICKER_PACK_PRICE_CENTS = 125;
export const TOTE_BAG_PRICE_CENTS = 150;

export const ITEMS: Item[] = [
  {
    id: "market-report",
    name: "Market report",
    priceCents: MARKET_REPORT_PRICE_CENTS,
    method: "x402",
    path: "/api/items/market-report",
  },
  {
    id: "price-feed",
    name: "Price feed",
    priceCents: PRICE_FEED_PRICE_CENTS,
    method: "x402",
    path: "/api/items/price-feed",
  },
  {
    id: "sticker-pack",
    name: "Sticker pack",
    priceCents: STICKER_PACK_PRICE_CENTS,
    method: "card",
    path: "/checkout?item=sticker-pack",
  },
  {
    id: "tote-bag",
    name: "Tote bag",
    priceCents: TOTE_BAG_PRICE_CENTS,
    method: "card",
    path: "/checkout?item=tote-bag",
  },
];

export const STORE_URL = "http://localhost:3000";

export const findItem = (id: string) => ITEMS.find((item) => item.id === id);

/** Dollars with two decimals, e.g. 100 -> "$1.00". */
export const formatUsd = (cents: number) => `$${(cents / 100).toFixed(2)}`;

/** USD amount string for a Crossmint exact-in order, e.g. 100 -> "1.00". */
export const usdAmount = (cents: number) => (cents / 100).toFixed(2);

// x402-protected fee the server pays to itself when the iOS app asks to unlock.
// Not in ITEMS, so it isn't shown in the store or offered to the agent.
// One price: the x402 route, the Crossmint card order, and unlockPriceText all derive from this.
export const UNLOCK_PRICE_CENTS = 100;
export const unlockPriceText = formatUsd(UNLOCK_PRICE_CENTS);
export const unlockAmountUsd = usdAmount(UNLOCK_PRICE_CENTS);
export const UNLOCK_FEE = {
  name: "Unlock fee",
  priceCents: UNLOCK_PRICE_CENTS,
  path: "/api/unlock-fee",
};

// Caps on the buyer wallet's x402 spending. One place for the agent and the unlock.
export const SPEND_PER_PAYMENT_CENTS = 500;
export const SPEND_PER_SESSION_CENTS = 2000;

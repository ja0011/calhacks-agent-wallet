// Store catalog shared by the store pages, the x402 route config, and the agent.
// All prices are integer cents.
export type PaymentMethod = "x402" | "card";

export type Item = {
  id: string;
  name: string;
  merchant: string;
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
    name: "Movie rental, one night",
    merchant: "Lumen Media",
    priceCents: MARKET_REPORT_PRICE_CENTS,
    method: "x402",
    path: "/api/items/market-report",
  },
  {
    id: "price-feed",
    name: "Day pass, no ads",
    merchant: "Lumen Media",
    priceCents: PRICE_FEED_PRICE_CENTS,
    method: "x402",
    path: "/api/items/price-feed",
  },
  {
    id: "sticker-pack",
    name: "Sticker pack",
    merchant: "Brightline Goods",
    priceCents: STICKER_PACK_PRICE_CENTS,
    method: "card",
    path: "/checkout?item=sticker-pack",
  },
  {
    id: "tote-bag",
    name: "Canvas tote bag",
    merchant: "Brightline Goods",
    priceCents: TOTE_BAG_PRICE_CENTS,
    method: "card",
    path: "/checkout?item=tote-bag",
  },
];

/** Shape used by the store page, GET /api/wallet, /api/chat, and list_items. */
export const listCatalog = () =>
  ITEMS.map(({ id, name, merchant, priceCents, method }) => ({
    id,
    name,
    merchant,
    price: formatUsd(priceCents),
    method,
  }));

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

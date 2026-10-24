// Store catalog shared by the store pages, the x402 route config, and the agent.
export type PaymentMethod = "x402" | "card";

export type Item = {
  id: string;
  name: string;
  priceCents: number;
  method: PaymentMethod;
  // x402 items: the protected API path. Card items: the checkout page.
  path: string;
};

export const ITEMS: Item[] = [
  {
    id: "market-report",
    name: "Market Report",
    priceCents: 1,
    method: "x402",
    path: "/api/items/market-report",
  },
  {
    id: "sneakers",
    name: "Sneakers",
    priceCents: 5900,
    method: "card",
    path: "/checkout",
  },
];

// x402-protected fee the server pays to itself when the iOS app asks to unlock.
// Not in ITEMS, so it isn't shown in the store or offered to the agent.
export const UNLOCK_FEE = {
  name: "Unlock fee",
  priceCents: 5,
  path: "/api/unlock-fee",
};

export const STORE_URL = "http://localhost:3000";

export const findItem = (id: string) => ITEMS.find((item) => item.id === id);

export const formatUsd = (cents: number) => `$${(cents / 100).toFixed(2)}`;

// Agent wallet: the simulated balance, the purchase list, and the x402 buyer client.
// Shared by the shopping agent and the unlock flow.
import { CdpX402Client } from "@coinbase/cdp-sdk/x402";
import { wrapFetchWithPayment } from "@x402/fetch";
import { formatUsd } from "./catalog.js";

// USDC on Base Sepolia has 6 decimals, so $0.01 = 10_000 atomic units.
const USDC_BASE_SEPOLIA = "0x036cbd53842c5426634e7929541ec2318f3dcf7e";
const ATOMIC_PER_CENT = 10_000n;

// Simulated wallet balance for the session; not read from the chain yet.
const STARTING_BALANCE_CENTS = 100;

export type Purchase = {
  item: string;
  amount: string;
  method: "x402" | "One-time card";
};

let balanceCents = STARTING_BALANCE_CENTS;
// SIMULATED SMART CONTRACT: funds locked by an unlock and released later by a timer.
// Nothing is held on-chain; this is only a number on the server.
let heldCents = 0;
const purchases: Purchase[] = [];

export const getBalanceCents = () => balanceCents;
export const getBalance = () => formatUsd(balanceCents);
export const getHeld = () => formatUsd(heldCents);
export const getPurchases = () => [...purchases];

export function spend(cents: number) {
  balanceCents -= cents;
}

export function recordPurchase(purchase: Purchase) {
  purchases.push(purchase);
}

// Takes `cents` out of the spendable balance before a payment, so a concurrent
// purchase can't spend the same money. Returns false if there isn't enough.
export function reserve(cents: number) {
  if (balanceCents < cents) return false;
  balanceCents -= cents;
  return true;
}

// Puts a reservation back after a failed payment.
export function cancelReservation(cents: number) {
  balanceCents += cents;
}

// SIMULATED SMART CONTRACT: moves reserved funds into the "held" balance and
// schedules their release back to spendable after `seconds`. A real version would
// be an on-chain escrow contract; here it's an in-memory timer that is lost on restart.
export function holdReserved(cents: number, seconds: number) {
  heldCents += cents;
  const releasesAt = new Date(Date.now() + seconds * 1000);
  setTimeout(() => {
    heldCents -= cents;
    balanceCents += cents;
  }, seconds * 1000);
  return releasesAt;
}

// Without a maxCumulativeSpendWindow, the cumulative cap covers the client's whole
// lifetime, i.e. one store-server session. Unlock fees count toward it too.
const x402Client = new CdpX402Client({
  environment: "development",
  spendControls: {
    maxAmountPerPayment: { atomic: 10n * ATOMIC_PER_CENT, asset: USDC_BASE_SEPOLIA },
    maxCumulativeSpend: { atomic: 100n * ATOMIC_PER_CENT, asset: USDC_BASE_SEPOLIA },
    allowedNetworks: ["eip155:84532"],
  },
});
export const fetchWithPayment = wrapFetchWithPayment(globalThis.fetch, x402Client);

// Public EVM address of the CDP buyer wallet that pays x402 fees.
export const getBuyerAddress = async () => (await x402Client.getAddresses()).evmAddress;

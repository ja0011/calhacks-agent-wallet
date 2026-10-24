// Unlock flow for the iOS app.
// With an orderId: the card checkout (Crossmint) must have delivered the USDC, then this pays
// the x402 unlock fee of the same amount. Without one: pay the fee from the wallet balance.
import { SpendControlError } from "@coinbase/cdp-sdk/x402";
import { STORE_URL, UNLOCK_FEE, unlockAmountUsd, formatUsd } from "./catalog.js";
import { CrossmintError, createOnrampOrder, getOnrampOrder, linkBuyerWallet } from "./onramp.js";
import {
  fetchWithPayment,
  getBalanceFields,
  getHeld,
  getOnchainUsdcCents,
  hold,
  invalidateBalanceCache,
  recordUnlock,
} from "./wallet.js";

// SIMULATED SMART CONTRACT: how long the unlock fee is displayed as "held".
export const HOLD_SECONDS = 120;

// Orders created by POST /api/unlock/start, and ones that already paid the x402 fee.
// In memory only; both are lost on restart.
const pendingOrders = new Set<string>();
const usedOrders = new Set<string>();
// Claimed while a payment is in progress, so two requests can't spend the same order.
const payingOrders = new Set<string>();

type BalanceFields = Awaited<ReturnType<typeof getBalanceFields>>;

type UnlockResult =
  | { status: 200; body: BalanceFields & { held: string; releasesAt: string } }
  | { status: number; body: { error: string; paymentStatus?: string | null; deliveryStatus?: string | null } };

// Links the buyer wallet (an already-linked wallet is fine) and creates a card order
// for the unlock price. The orderId has to come back to POST /api/unlock.
export async function startUnlock() {
  await linkBuyerWallet();
  const { clientSecret, order } = await createOnrampOrder(unlockAmountUsd);
  const orderId = order.orderId as string;
  pendingOrders.add(orderId);
  return { orderId, clientSecret, amount: unlockAmountUsd };
}

export async function unlock(orderId?: string): Promise<UnlockResult> {
  if (orderId !== undefined) {
    const gate = await gateCardOrder(orderId);
    if (gate) return gate;
    // The USDC just arrived, so don't answer the balance check from a stale cache.
    invalidateBalanceCache();
  }

  try {
    const result = await payUnlockFee();
    if (orderId !== undefined && result.status === 200) {
      pendingOrders.delete(orderId);
      usedOrders.add(orderId);
    }
    return result;
  } finally {
    if (orderId !== undefined) payingOrders.delete(orderId);
  }
}

// null means the order may be paid. Otherwise the response to send back.
async function gateCardOrder(orderId: string): Promise<UnlockResult | null> {
  if (!orderId) return { status: 400, body: { error: "orderId must be a non-empty string." } };
  if (usedOrders.has(orderId)) {
    return { status: 409, body: { error: "This order was already used to unlock." } };
  }
  if (!pendingOrders.has(orderId)) {
    return { status: 404, body: { error: "Unknown unlock order. Call POST /api/unlock/start first." } };
  }
  if (payingOrders.has(orderId)) {
    return { status: 409, body: { error: "This unlock payment is already in progress." } };
  }
  payingOrders.add(orderId);

  let delivery;
  try {
    delivery = await getOnrampOrder(orderId);
  } catch (error) {
    payingOrders.delete(orderId);
    if (error instanceof CrossmintError) {
      return { status: error.status, body: { error: error.message } };
    }
    throw error;
  }
  if (delivery.deliveryStatus !== "completed") {
    payingOrders.delete(orderId);
    return {
      status: 409,
      body: {
        error: "USDC has not been delivered yet.",
        paymentStatus: delivery.paymentStatus,
        deliveryStatus: delivery.deliveryStatus,
      },
    };
  }
  return null;
}

async function payUnlockFee(): Promise<UnlockResult> {
  const fee = UNLOCK_FEE.priceCents;

  let balanceCents: number;
  try {
    balanceCents = await getOnchainUsdcCents();
  } catch {
    return { status: 503, body: { error: "On-chain USDC balance is unavailable." } };
  }
  if (balanceCents < fee) {
    return {
      status: 402,
      body: { error: `Insufficient balance: ${formatUsd(balanceCents)} available, ${formatUsd(fee)} needed to unlock.` },
    };
  }

  try {
    const response = await fetchWithPayment(`${STORE_URL}${UNLOCK_FEE.path}`);
    if (!response.ok) {
      return { status: 502, body: { error: `Unlock fee payment failed (HTTP ${response.status}).` } };
    }
  } catch (error) {
    if (error instanceof SpendControlError) {
      return { status: 403, body: { error: `Blocked by spend controls (${error.code}).` } };
    }
    console.error("Unlock fee payment failed:", error instanceof Error ? error.message : "unknown error");
    return { status: 502, body: { error: "Unlock fee payment failed. Check the server logs." } };
  }

  // The fee moved real USDC, so the on-chain balance drops by itself. The hold is display-only.
  invalidateBalanceCache();
  recordUnlock();
  const releasesAt = hold(fee, HOLD_SECONDS);
  return {
    status: 200,
    body: { ...(await getBalanceFields()), held: getHeld(), releasesAt: releasesAt.toISOString() },
  };
}

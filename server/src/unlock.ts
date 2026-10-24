// Unlock flow for the iOS app: pay the x402 unlock fee, then show that amount as
// "held" for HOLD_SECONDS.
import { SpendControlError } from "@coinbase/cdp-sdk/x402";
import { STORE_URL, UNLOCK_FEE, formatUsd } from "./catalog.js";
import {
  fetchWithPayment,
  getBalanceFields,
  getHeld,
  getOnchainUsdcCents,
  hold,
  invalidateBalanceCache,
} from "./wallet.js";

// SIMULATED SMART CONTRACT: how long the unlock fee is displayed as "held".
export const HOLD_SECONDS = 120;

type BalanceFields = Awaited<ReturnType<typeof getBalanceFields>>;

type UnlockResult =
  | { status: 200; body: BalanceFields & { held: string; releasesAt: string } }
  | { status: number; body: { error: string } };

export async function unlock(): Promise<UnlockResult> {
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
  const releasesAt = hold(fee, HOLD_SECONDS);
  return {
    status: 200,
    body: { ...(await getBalanceFields()), held: getHeld(), releasesAt: releasesAt.toISOString() },
  };
}

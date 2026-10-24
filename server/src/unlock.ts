// Unlock flow for the iOS app: pay the x402 unlock fee, then hold that amount
// for HOLD_SECONDS before returning it to the spendable balance.
import { SpendControlError } from "@coinbase/cdp-sdk/x402";
import { STORE_URL, UNLOCK_FEE, formatUsd } from "./catalog.js";
import { cancelReservation, fetchWithPayment, getBalance, getHeld, holdReserved, reserve } from "./wallet.js";

// SIMULATED SMART CONTRACT: how long the unlock fee stays "held" before release.
export const HOLD_SECONDS = 120;

type UnlockResult =
  | { status: 200; body: { balance: string; held: string; releasesAt: string } }
  | { status: number; body: { error: string } };

export async function unlock(): Promise<UnlockResult> {
  const fee = UNLOCK_FEE.priceCents;
  if (!reserve(fee)) {
    return {
      status: 402,
      body: { error: `Insufficient balance: ${getBalance()} available, ${formatUsd(fee)} needed to unlock.` },
    };
  }

  try {
    const response = await fetchWithPayment(`${STORE_URL}${UNLOCK_FEE.path}`);
    if (!response.ok) {
      cancelReservation(fee);
      return { status: 502, body: { error: `Unlock fee payment failed (HTTP ${response.status}).` } };
    }
  } catch (error) {
    cancelReservation(fee);
    if (error instanceof SpendControlError) {
      return { status: 403, body: { error: `Blocked by spend controls (${error.code}).` } };
    }
    console.error("Unlock fee payment failed:", error instanceof Error ? error.message : "unknown error");
    return { status: 502, body: { error: "Unlock fee payment failed. Check the server logs." } };
  }

  const releasesAt = holdReserved(fee, HOLD_SECONDS);
  return { status: 200, body: { balance: getBalance(), held: getHeld(), releasesAt: releasesAt.toISOString() } };
}

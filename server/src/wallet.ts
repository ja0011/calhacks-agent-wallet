// Agent wallet: the on-chain USDC balance, the purchase list, and the x402 buyer client.
// Shared by the shopping agent, the unlock flow, and the one-time card flow.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { CdpX402Client } from "@coinbase/cdp-sdk/x402";
import { wrapFetchWithPayment } from "@x402/fetch";
import { createPublicClient, erc20Abi, http } from "viem";
import { baseSepolia } from "viem/chains";
import {
  SPEND_PER_PAYMENT_CENTS,
  SPEND_PER_SESSION_CENTS,
  UNLOCK_PRICE_CENTS,
  formatUsd,
} from "./catalog.js";

// USDC on Base Sepolia has 6 decimals, so $0.01 = 10_000 atomic units.
const USDC_BASE_SEPOLIA = "0x036cbd53842c5426634e7929541ec2318f3dcf7e";
const ATOMIC_PER_CENT = 10_000n;

const BASE_SEPOLIA_RPC_URL = "https://sepolia.base.org";
const BALANCE_CACHE_MS = 5_000;

export type Purchase = {
  item: string;
  amount: string;
  method: "x402" | "One-time card";
};

export type ActivityMethod = "Card" | "x402" | "One-time card";
export type ActivityDirection = "in" | "out";

export type ActivityEntry = {
  label: string;
  method: ActivityMethod;
  amountCents: number;
  direction: ActivityDirection;
  at: string;
};

const parsedBankStart = Number.parseInt(process.env.BANK_START_CENTS ?? "", 10);
export const BANK_START_CENTS =
  Number.isInteger(parsedBankStart) && parsedBankStart >= 0 ? parsedBankStart : 284_736;

const STATE_PATH = fileURLToPath(new URL("../.data/state.json", import.meta.url));
const ACTIVITY_LIMIT = 20;

type PersistedState = {
  bankCents: number;
  activity: ActivityEntry[];
  countedOrderIds: string[];
  orderAmounts: Record<string, number>;
};

function loadState(): PersistedState {
  try {
    const raw = JSON.parse(readFileSync(STATE_PATH, "utf8")) as Partial<PersistedState>;
    return {
      bankCents: typeof raw.bankCents === "number" && Number.isFinite(raw.bankCents) ? raw.bankCents : BANK_START_CENTS,
      activity: Array.isArray(raw.activity) ? raw.activity : [],
      countedOrderIds: Array.isArray(raw.countedOrderIds) ? raw.countedOrderIds : [],
      orderAmounts: raw.orderAmounts && typeof raw.orderAmounts === "object" ? raw.orderAmounts : {},
    };
  } catch {
    return { bankCents: BANK_START_CENTS, activity: [], countedOrderIds: [], orderAmounts: {} };
  }
}

let { bankCents, activity, countedOrderIds, orderAmounts } = loadState();
const countedOrders = new Set(countedOrderIds);

function persist() {
  mkdirSync(fileURLToPath(new URL("../.data", import.meta.url)), { recursive: true });
  writeFileSync(
    STATE_PATH,
    JSON.stringify({ bankCents, activity, countedOrderIds: [...countedOrders], orderAmounts }, null, 2),
  );
}

const formatBankUsd = (cents: number) => {
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  return `${sign}$${Math.floor(abs / 100).toLocaleString("en-US")}.${String(abs % 100).padStart(2, "0")}`;
};

function recordActivity(entry: Omit<ActivityEntry, "at">) {
  activity.push({ ...entry, at: new Date().toISOString() });
  persist();
}

const VAULT_LOCK_MS = 14 * 24 * 60 * 60 * 1000;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

export const getVault = () => {
  const unlocks = activity
    .filter((entry) => entry.label === "Unlock")
    .sort((a, b) => a.at.localeCompare(b.at));
  if (unlocks.length === 0) {
    return { lockedTotal: null, entries: [] as const };
  }
  const now = Date.now();
  const entries = unlocks.map((entry) => {
    const lockedAt = new Date(entry.at);
    const releasesAt = new Date(lockedAt.getTime() + VAULT_LOCK_MS);
    const daysLeft = Math.max(0, Math.floor((releasesAt.getTime() - now) / MS_PER_DAY));
    return {
      amount: formatUsd(entry.amountCents),
      lockedAt: lockedAt.toISOString(),
      releasesAt: releasesAt.toISOString(),
      daysLeft,
    };
  });
  const lockedTotalCents = unlocks.reduce((sum, entry) => sum + entry.amountCents, 0);
  return { lockedTotal: formatUsd(lockedTotalCents), entries };
};

export const getBank = () => ({ balance: formatBankUsd(bankCents) });
export const getActivity = () =>
  [...activity]
    .reverse()
    .slice(0, ACTIVITY_LIMIT)
    .map(({ label, method, amountCents, direction, at }) => ({
      label,
      method,
      amount: formatUsd(amountCents),
      direction,
      at,
    }));

export function rememberCardOrder(orderId: string, amountCents: number) {
  orderAmounts[orderId] = amountCents;
  persist();
}

// Credits the wallet from a completed Crossmint order exactly once. Subtracts that
// order's total from the simulated bank. A repeated poll with the same orderId is a no-op.
export function recordCompletedCardOrder(orderId: string, amountCents?: number) {
  if (countedOrders.has(orderId)) return;
  const cents = amountCents ?? orderAmounts[orderId];
  if (cents === undefined) return;
  countedOrders.add(orderId);
  bankCents -= cents;
  delete orderAmounts[orderId];
  recordActivity({ label: "Added to wallet", method: "Card", amountCents: cents, direction: "in" });
}

export function recordUnlock() {
  recordActivity({ label: "Unlock", method: "x402", amountCents: UNLOCK_PRICE_CENTS, direction: "out" });
}

// SIMULATED SMART CONTRACT: funds locked by an unlock and released later by a timer.
// Display-only: the held amount is NOT subtracted from the on-chain balance, and nothing
// is locked on-chain. It's an in-memory number that is lost on restart.
let heldCents = 0;
const purchases: Purchase[] = [];

export const getHeld = () => formatUsd(heldCents);
export const getPurchases = () => [...purchases];

export function recordPurchase(purchase: Purchase, amountCents: number) {
  purchases.push(purchase);
  recordActivity({ label: purchase.item, method: purchase.method, amountCents, direction: "out" });
}

export function resetBank() {
  bankCents = BANK_START_CENTS;
  activity = [];
  countedOrders.clear();
  orderAmounts = {};
  persist();
}

// SIMULATED SMART CONTRACT: adds `cents` to the held amount for `seconds`. Display-only.
export function hold(cents: number, seconds: number) {
  heldCents += cents;
  const releasesAt = new Date(Date.now() + seconds * 1000);
  setTimeout(() => {
    heldCents -= cents;
  }, seconds * 1000);
  return releasesAt;
}

// Without a maxCumulativeSpendWindow, the cumulative cap covers the client's whole
// lifetime, i.e. one store-server session. Unlock fees count toward it too.
const x402Client = new CdpX402Client({
  environment: "development",
  spendControls: {
    maxAmountPerPayment: { atomic: BigInt(SPEND_PER_PAYMENT_CENTS) * ATOMIC_PER_CENT, asset: USDC_BASE_SEPOLIA },
    maxCumulativeSpend: { atomic: BigInt(SPEND_PER_SESSION_CENTS) * ATOMIC_PER_CENT, asset: USDC_BASE_SEPOLIA },
    allowedNetworks: ["eip155:84532"],
  },
});
export const fetchWithPayment = wrapFetchWithPayment(globalThis.fetch, x402Client);
console.log(`[startup] ${new Date().toISOString()} buyer x402 client constructed (no network call)`);

// Public EVM address of the CDP buyer wallet that pays x402 fees.
export const getBuyerAddress = async () => (await x402Client.getAddresses()).evmAddress;

const rpc = createPublicClient({ chain: baseSepolia, transport: http(BASE_SEPOLIA_RPC_URL) });

let lastKnownCents: number | undefined;
let lastReadAt = 0;
let inFlight: Promise<number> | undefined;

async function readOnchainUsdcCents() {
  const atomic = await rpc.readContract({
    address: USDC_BASE_SEPOLIA,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [await getBuyerAddress()],
  });
  return Number(atomic / ATOMIC_PER_CENT);
}

// The buyer wallet's USDC balance on Base Sepolia in whole cents (rounded down).
// Cached for BALANCE_CACHE_MS; if the read fails, returns the last known value.
// Throws only if the balance has never been read successfully.
export async function getOnchainUsdcCents(): Promise<number> {
  if (lastKnownCents !== undefined && Date.now() - lastReadAt < BALANCE_CACHE_MS) {
    return lastKnownCents;
  }
  inFlight ??= readOnchainUsdcCents()
    .then((cents) => {
      lastKnownCents = cents;
      lastReadAt = Date.now();
      return cents;
    })
    .catch((error) => {
      console.error("On-chain USDC balance read failed:", error instanceof Error ? error.message : "unknown error");
      if (lastKnownCents === undefined) throw new Error("On-chain USDC balance is unavailable.");
      return lastKnownCents;
    })
    .finally(() => {
      inFlight = undefined;
    });
  return inFlight;
}

// Forces the next read to go to the chain, e.g. right after a payment.
export function invalidateBalanceCache() {
  lastReadAt = 0;
}

export async function getBalance() {
  return formatUsd(await getOnchainUsdcCents());
}

// The `balance` fields shared by /api/wallet, /api/chat, and /api/unlock responses.
export async function getBalanceFields() {
  try {
    return { balance: await getBalance(), balanceSource: "onchain" as const };
  } catch {
    return { balance: null, balanceSource: "unavailable" as const };
  }
}

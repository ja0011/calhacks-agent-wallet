// Agent wallet: the on-chain USDC balance, the purchase list, and the x402 buyer client.
// Shared by the shopping agent, the unlock flow, and the one-time card flow.
import { CdpX402Client } from "@coinbase/cdp-sdk/x402";
import { wrapFetchWithPayment } from "@x402/fetch";
import { createPublicClient, erc20Abi, http } from "viem";
import { baseSepolia } from "viem/chains";
import { formatUsd } from "./catalog.js";

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

// SIMULATED SMART CONTRACT: funds locked by an unlock and released later by a timer.
// Display-only: the held amount is NOT subtracted from the on-chain balance, and nothing
// is locked on-chain. It's an in-memory number that is lost on restart.
let heldCents = 0;
const purchases: Purchase[] = [];

export const getHeld = () => formatUsd(heldCents);
export const getPurchases = () => [...purchases];

export function recordPurchase(purchase: Purchase) {
  purchases.push(purchase);
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
    maxAmountPerPayment: { atomic: 10n * ATOMIC_PER_CENT, asset: USDC_BASE_SEPOLIA },
    maxCumulativeSpend: { atomic: 100n * ATOMIC_PER_CENT, asset: USDC_BASE_SEPOLIA },
    allowedNetworks: ["eip155:84532"],
  },
});
export const fetchWithPayment = wrapFetchWithPayment(globalThis.fetch, x402Client);

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

// Crossmint staging onramp: fund the CDP buyer wallet with testnet USDC on Base Sepolia by card.
// Docs: https://docs.crossmint.com/onramp/guides/onramp-to-external-wallets
import { Router, type ErrorRequestHandler } from "express";
import { getBuyerAddress, rememberCardOrder, recordCompletedCardOrder } from "./wallet.js";

const CROSSMINT_API_URL = "https://staging.crossmint.com/api";
const CHAIN = "base-sepolia";
const USDC_TOKEN_LOCATOR = "base-sepolia:0x036CbD53842c5426634e7929541eC2318f3dCF7e";
const DEFAULT_AMOUNT = "5";

export class CrossmintError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function requireEnv(name: string) {
  const value = process.env[name];
  if (!value) throw new CrossmintError(500, `${name} is not set in server/.env.`);
  return value;
}

async function crossmint(method: string, path: string, body?: unknown) {
  const response = await fetch(`${CROSSMINT_API_URL}${path}`, {
    method,
    headers: {
      "X-API-KEY": requireEnv("CROSSMINT_SERVER_API_KEY"),
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new CrossmintError(response.status, data?.message ?? `Crossmint returned HTTP ${response.status}.`);
  }
  return data;
}

// Links the buyer wallet to the Crossmint user. Crossmint creates the user if the email
// locator doesn't exist yet. No proof is sent: ownership proof is only required above
// Crossmint's volume thresholds. Returns null when Crossmint says the wallet is already linked.
export async function linkBuyerWallet() {
  const userLocator = `email:${requireEnv("CROSSMINT_USER_EMAIL")}`;
  const address = await getBuyerAddress();
  try {
    return await crossmint("PUT", `/2025-06-09/users/${userLocator}/linked-wallets/${address}`, {
      chain: CHAIN,
    });
  } catch (error) {
    if (error instanceof CrossmintError && /already linked/i.test(error.message)) return null;
    throw error;
  }
}

// `amount` is a USD string such as "1.00" (exact-in: what the card is charged).
export async function createOnrampOrder(amount: string) {
  const { clientSecret, order } = await crossmint("POST", "/2022-06-09/orders", {
    lineItems: [
      {
        tokenLocator: USDC_TOKEN_LOCATOR,
        executionParameters: { mode: "exact-in", amount },
      },
    ],
    payment: { method: "card", receiptEmail: requireEnv("CROSSMINT_USER_EMAIL") },
    recipient: { walletAddress: await getBuyerAddress() },
  });
  rememberCardOrder(order.orderId as string, Math.round(Number(amount) * 100));
  return { clientSecret: clientSecret as string, order };
}

// Get Order returns the order itself. Delivery status is per line item.
export async function getOnrampOrder(orderId: string) {
  const order = await crossmint("GET", `/2022-06-09/orders/${encodeURIComponent(orderId)}`);
  const delivery = order.lineItems?.[0]?.delivery;
  if (delivery?.status === "completed") {
    const quoted = order.lineItems?.[0]?.executionParameters?.amount;
    const amountCents =
      typeof quoted === "string" && /^\d+(\.\d{1,2})?$/.test(quoted) ? Math.round(Number(quoted) * 100) : undefined;
    recordCompletedCardOrder(order.orderId ?? orderId, amountCents);
  }
  return {
    paymentStatus: (order.payment?.status ?? null) as string | null,
    deliveryStatus: (delivery?.status ?? null) as string | null,
    txId: (delivery?.txId ?? null) as string | null,
  };
}

export const onrampRouter = Router();

onrampRouter.post("/link-wallet", async (_req, res) => {
  const linked = await linkBuyerWallet();
  if (!linked) {
    res.json({ alreadyLinked: true });
    return;
  }
  res.json({
    address: linked.address,
    chain: linked.chain,
    verified: linked.ownership?.verified ?? false,
  });
});

onrampRouter.post("/order", async (req, res) => {
  const amount = req.body?.amount === undefined ? DEFAULT_AMOUNT : String(req.body.amount);
  if (!/^\d+(\.\d{1,2})?$/.test(amount) || Number(amount) <= 0) {
    res.status(400).json({ error: 'amount must be a positive USD amount like "5" or "2.50".' });
    return;
  }
  const { clientSecret, order } = await createOnrampOrder(amount);
  res.json({
    orderId: order.orderId,
    clientSecret,
    quote: order.quote,
    paymentStatus: order.payment?.status,
  });
});

onrampRouter.get("/order/:orderId", async (req, res) => {
  res.json(await getOnrampOrder(req.params.orderId));
});

// Client API keys are publishable; the server key never leaves this module.
onrampRouter.get("/config", (_req, res) => {
  res.json({ clientApiKey: requireEnv("CROSSMINT_CLIENT_API_KEY"), environment: "staging" });
});

// Express 5 forwards rejected promises from async handlers here.
const handleError: ErrorRequestHandler = (error, _req, res, _next) => {
  const status = error instanceof CrossmintError ? error.status : 502;
  const message = error instanceof CrossmintError ? error.message : "Onramp request failed.";
  console.error(`Onramp error (${status}):`, message);
  res.status(status).json({ error: message });
};
onrampRouter.use(handleError);

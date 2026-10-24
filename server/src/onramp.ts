// Crossmint staging onramp: fund the CDP buyer wallet with testnet USDC on Base Sepolia by card.
// Docs: https://docs.crossmint.com/onramp/guides/onramp-to-external-wallets
import { Router, type ErrorRequestHandler } from "express";
import { getBuyerAddress } from "./wallet.js";

const CROSSMINT_API_URL = "https://staging.crossmint.com/api";
const CHAIN = "base-sepolia";
const USDC_TOKEN_LOCATOR = "base-sepolia:0x036CbD53842c5426634e7929541eC2318f3dCF7e";
const DEFAULT_AMOUNT = "5";

class CrossmintError extends Error {
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

export const onrampRouter = Router();

// Links the buyer wallet to the Crossmint user, which must happen before an onramp order
// can deliver to it. Crossmint creates the user if the email locator doesn't exist yet.
// No proof is sent: ownership proof is only required above Crossmint's volume thresholds.
onrampRouter.post("/link-wallet", async (_req, res) => {
  const userLocator = `email:${requireEnv("CROSSMINT_USER_EMAIL")}`;
  const address = await getBuyerAddress();
  const linked = await crossmint("PUT", `/2025-06-09/users/${userLocator}/linked-wallets/${address}`, {
    chain: CHAIN,
  });
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
  res.json({
    orderId: order.orderId,
    clientSecret,
    quote: order.quote,
    paymentStatus: order.payment?.status,
  });
});

// Get Order returns the order itself (not wrapped). Delivery is tracked per line item.
onrampRouter.get("/order/:orderId", async (req, res) => {
  const order = await crossmint("GET", `/2022-06-09/orders/${encodeURIComponent(req.params.orderId)}`);
  const delivery = order.lineItems?.[0]?.delivery;
  res.json({
    paymentStatus: order.payment?.status ?? null,
    deliveryStatus: delivery?.status ?? null,
    txId: delivery?.txId ?? null,
  });
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

// Fake store with one x402-protected API route, based on Coinbase's seller quickstart:
// https://docs.cdp.coinbase.com/x402/seller/quickstart
import "./env.js";
import express, { type RequestHandler } from "express";
import { createX402Server } from "@coinbase/cdp-sdk/x402";
import { paymentMiddlewareFromHTTPServer } from "@x402/express";
import { runAgent } from "./agent.js";
import {
  ITEMS,
  SPEND_PER_PAYMENT_CENTS,
  SPEND_PER_SESSION_CENTS,
  UNLOCK_FEE,
  findItem,
  formatUsd,
  unlockPriceText,
} from "./catalog.js";
import { chargeAtCheckout, retryLastCard } from "./one-time-card.js";
import { CrossmintError, onrampRouter } from "./onramp.js";
import { startUnlock, unlock } from "./unlock.js";
import { getActivity, getBalanceFields, getBank, getHeld, getPurchases, resetBank } from "./wallet.js";

const PORT = 3000;
const BASE_SEPOLIA = "eip155:84532";
const ATTEMPT_TIMEOUT_MS = 20_000;
const ATTEMPT_BACKOFF_MS = 2_000;
const RETRY_EVERY_MS = 30_000;

const startupLog = (step: string) => console.log(`[startup] ${new Date().toISOString()} ${step}`);

// Reaching this line means every import finished. None of them make a network call.
startupLog("imports finished");

const x402Routes = {
  ...Object.fromEntries(
    ITEMS.filter((item) => item.method === "x402").map((item) => [
      `GET ${item.path}`,
      { price: formatUsd(item.priceCents), networks: [BASE_SEPOLIA], description: item.name },
    ]),
  ),
  [`GET ${UNLOCK_FEE.path}`]: {
    price: formatUsd(UNLOCK_FEE.priceCents),
    networks: [BASE_SEPOLIA],
    description: UNLOCK_FEE.name,
  },
};

// Set once createX402Server succeeds. Until then the protected routes answer 503.
let x402Ready: RequestHandler | undefined;

const app = express();
app.use(express.urlencoded({ extended: false }));
app.use(express.json());
app.use((req, res, next) => {
  if (!(`${req.method} ${req.path}` in x402Routes)) {
    next();
    return;
  }
  if (!x402Ready) {
    res.status(503).json({ error: "Payment system is starting, try again in a moment" });
    return;
  }
  return x402Ready(req, res, next);
});

const escapeHtml = (value: string) =>
  value.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

const page = (title: string, body: string) => `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 640px; margin: 40px auto; padding: 0 16px; color: #222; }
    h1 { font-size: 1.6rem; }
    .item { border: 1px solid #ddd; border-radius: 8px; padding: 16px; margin: 16px 0; }
    .item h2 { margin: 0 0 4px; font-size: 1.2rem; }
    .price { font-weight: bold; }
    .muted { color: #666; font-size: 0.9rem; }
    label { display: block; margin: 12px 0 4px; font-weight: 600; }
    input { width: 100%; padding: 8px; font-size: 1rem; box-sizing: border-box; }
    button, .button { display: inline-block; margin-top: 16px; padding: 10px 20px; font-size: 1rem;
      background: #0052ff; color: #fff; border: none; border-radius: 6px; text-decoration: none; cursor: pointer; }
    code { background: #f3f3f3; padding: 2px 4px; border-radius: 4px; }
  </style>
</head>
<body>
${body}
</body>
</html>`;

app.get("/", (_req, res) => {
  const cards = ITEMS.map((item) =>
    item.method === "x402"
      ? `<div class="item" id="${item.id}">
  <h2>${item.name}</h2>
  <p class="price">${formatUsd(item.priceCents)}</p>
  <p class="muted">Paid with x402 (USDC on Base Sepolia).
    Endpoint: <code>GET ${item.path}</code></p>
</div>`
      : `<div class="item" id="${item.id}">
  <h2>${item.name}</h2>
  <p class="price">${formatUsd(item.priceCents)}</p>
  <p class="muted">Paid with the card checkout form.</p>
  <a class="button" href="${item.path}">Buy ${item.name}</a>
</div>`,
  ).join("\n");
  res.send(page("Fake Store", `<h1>Fake Store</h1>\n${cards}`));
});

const marketReport = findItem("market-report")!;
app.get(marketReport.path, (_req, res) => {
  res.json({
    item: marketReport.name,
    price: formatUsd(marketReport.priceCents),
    generatedAt: new Date().toISOString(),
    summary: "Fake data: markets were mostly flat today.",
    highlights: ["Tech stocks rose 0.4%.", "Energy stocks fell 0.2%."],
  });
});

const priceFeed = findItem("price-feed")!;
app.get(priceFeed.path, (_req, res) => {
  res.json({
    item: priceFeed.name,
    price: formatUsd(priceFeed.priceCents),
    generatedAt: new Date().toISOString(),
    prices: [
      { asset: "ETH", usd: "3200.50" },
      { asset: "BTC", usd: "67420.00" },
    ],
  });
});

// x402-protected: the payment middleware only lets this through after the fee is paid.
app.get(UNLOCK_FEE.path, (_req, res) => {
  res.json({ ok: true });
});

// Card checkout for an unlock: a Crossmint order for the unlock price, delivered to the buyer wallet.
app.post("/api/unlock/start", async (_req, res) => {
  try {
    res.json(await startUnlock());
  } catch (error) {
    const status = error instanceof CrossmintError ? error.status : 502;
    const message = error instanceof CrossmintError ? error.message : "Couldn't start the unlock checkout.";
    console.error(`Unlock start failed (${status}):`, message);
    res.status(status).json({ error: message });
  }
});

// Pays the x402 unlock fee. With { orderId }, only after that Crossmint order has delivered.
// Without one, pays from the wallet balance.
app.post("/api/unlock", async (req, res) => {
  const orderId = req.body?.orderId;
  if (orderId !== undefined && typeof orderId !== "string") {
    res.status(400).json({ error: "orderId must be a string." });
    return;
  }
  const result = await unlock(orderId);
  res.status(result.status).json(result.body);
});

app.use("/api/onramp", onrampRouter);

app.post("/api/dev/reset-bank", (_req, res) => {
  resetBank();
  res.json({ bank: getBank(), activity: getActivity() });
});

app.get("/api/wallet", async (_req, res) => {
  const balanceFields = await getBalanceFields();
  res
    .status(balanceFields.balance === null ? 503 : 200)
    .json({
      ...balanceFields,
      held: getHeld(),
      purchases: getPurchases(),
      bank: getBank(),
      activity: getActivity(),
      unlockPriceText,
      limits: {
        perPaymentText: formatUsd(SPEND_PER_PAYMENT_CENTS),
        perSessionText: formatUsd(SPEND_PER_SESSION_CENTS),
      },
    });
});

const findCardItem = (id: unknown) => {
  const item = typeof id === "string" ? findItem(id) : undefined;
  return item?.method === "card" ? item : undefined;
};

app.get("/checkout", (req, res) => {
  const item = findCardItem(req.query.item);
  if (!item) {
    res.status(404).send(page("Not found", `<h1>Item not found</h1><p><a href="/">Back to store</a></p>`));
    return;
  }
  res.send(
    page(
      `Checkout - ${item.name}`,
      `<h1>Checkout</h1>
<p>Item: <strong>${item.name}</strong>, total <strong>${formatUsd(item.priceCents)}</strong></p>
<form method="post" action="/api/checkout">
  <input type="hidden" name="item" value="${item.id}">

  <label for="name">Name on card</label>
  <input id="name" name="name" type="text" autocomplete="cc-name" required>

  <label for="card-number">Card number</label>
  <input id="card-number" name="cardNumber" type="text" inputmode="numeric" autocomplete="cc-number" required>

  <label for="expiry">Expiry (MM/YY)</label>
  <input id="expiry" name="expiry" type="text" placeholder="MM/YY" autocomplete="cc-exp" required>

  <label for="cvc">CVC</label>
  <input id="cvc" name="cvc" type="text" inputmode="numeric" autocomplete="cc-csc" required>

  <button type="submit">Pay</button>
</form>`,
    ),
  );
});

// Never log the request body: it contains the card number and CVC.
app.post("/api/checkout", async (req, res) => {
  const field = (key: string) => (typeof req.body?.[key] === "string" ? (req.body[key] as string) : "");
  const item = findCardItem(field("item"));
  const name = field("name");
  if (!item) {
    res.status(404).send(page("Not found", `<h1>Item not found</h1><p><a href="/">Back to store</a></p>`));
    return;
  }

  try {
    const result = await chargeAtCheckout({
      number: field("cardNumber"),
      expiry: field("expiry"),
      cvc: field("cvc"),
      itemId: item.id,
    });
    if (!result.approved) {
      res.status(402).send(
        page(
          "Payment declined",
          `<h1 id="result" data-outcome="declined">Payment declined</h1>
<p>Reason: <code>${escapeHtml(result.reason ?? "declined")}</code></p>
<p><a href="/">Back to store</a></p>`,
        ),
      );
      return;
    }
    res.send(
      page(
        "Payment successful",
        `<h1 id="result" data-outcome="approved">Payment successful</h1>
<p>Thanks${name ? `, ${escapeHtml(name)}` : ""}! Your order for <strong>${item.name}</strong> (${formatUsd(item.priceCents)}) is confirmed.</p>
<p><a href="/">Back to store</a></p>`,
      ),
    );
  } catch (error) {
    console.error("Checkout charge failed:", error instanceof Error ? error.message : "unknown error");
    res.status(502).send(page("Payment error", `<h1 id="result" data-outcome="error">Payment error</h1>`));
  }
});

// Demo: charges the last used one-time card again. It was cancelled, so it should decline.
app.get("/api/card-demo/retry", async (_req, res) => {
  const result = await retryLastCard();
  res.status(result.ok ? 200 : 404).json(result);
});

app.post("/api/chat", async (req, res) => {
  const message = req.body?.message;
  if (typeof message !== "string" || !message.trim()) {
    res.status(400).json({ error: 'Send JSON like { "message": "Buy the market report" }.' });
    return;
  }
  try {
    res.json(await runAgent(message));
  } catch (error) {
    console.error("Agent failed:", error instanceof Error ? error.message : "unknown error");
    res.status(500).json({ error: "The agent failed. Check the server logs." });
  }
});

startupLog("routes registered");
startupLog("listen: start");
app.listen(PORT, () => {
  startupLog("listen: done");
  console.log(`Store running at http://localhost:${PORT}`);
});

// createX402Server has no way to skip its own account lookup or facilitator sync:
// both happen before it returns. @x402/express's syncFacilitatorOnStart only skips
// a second sync inside the middleware, so it cannot unblock startup.
void connectX402();

function installX402(server: Awaited<ReturnType<typeof createX402Server>>, label: string) {
  if (x402Ready) return;
  // Already initialized inside createX402Server, so the middleware must not sync again.
  x402Ready = paymentMiddlewareFromHTTPServer(server, undefined, undefined, false);
  startupLog(`${label}: done, payments go to ${server.payToEvmAddress}`);
}

// One attempt. A timeout rejects this call but a late success still installs.
async function attemptX402(label: string) {
  if (x402Ready) return;
  startupLog(`${label}: start`);
  let timer: NodeJS.Timeout | undefined;
  const setup = createX402Server({
    environment: "development",
    payToConfig: { type: "eoa", accountName: "store-receiver" },
    routes: x402Routes,
  });
  setup.then((server) => installX402(server, label)).catch(() => {});
  try {
    await Promise.race([
      setup,
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error(`${label} timed out after ${ATTEMPT_TIMEOUT_MS / 1000}s`)),
          ATTEMPT_TIMEOUT_MS,
        );
      }),
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

async function connectX402() {
  const failure = (error: unknown) => (error instanceof Error ? error.message : "unknown error");
  for (let attempt = 1; attempt <= 3 && !x402Ready; attempt++) {
    try {
      await attemptX402(`createX402Server attempt ${attempt}`);
    } catch (error) {
      startupLog(`createX402Server attempt ${attempt}: ${failure(error)}`);
    }
    if (!x402Ready && attempt < 3) {
      await new Promise((resolve) => setTimeout(resolve, ATTEMPT_BACKOFF_MS));
    }
  }
  if (x402Ready) return;
  console.error(
    `[startup] ${new Date().toISOString()} x402 setup failed after 3 attempts; the store is up and will retry every 30s`,
  );
  for (let retry = 1; !x402Ready; retry++) {
    await new Promise((resolve) => setTimeout(resolve, RETRY_EVERY_MS));
    if (x402Ready) return;
    try {
      await attemptX402(`createX402Server retry ${retry}`);
    } catch (error) {
      startupLog(`createX402Server retry ${retry}: ${failure(error)}`);
    }
  }
}

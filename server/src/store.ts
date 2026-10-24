// Fake store with one x402-protected API route, based on Coinbase's seller quickstart:
// https://docs.cdp.coinbase.com/x402/seller/quickstart
import "./env.js";
import express from "express";
import { createX402Server } from "@coinbase/cdp-sdk/x402";
import { paymentMiddlewareFromHTTPServer } from "@x402/express";
import { runAgent } from "./agent.js";
import { ITEMS, UNLOCK_FEE, findItem, formatUsd } from "./catalog.js";
import { chargeAtCheckout, retryLastCard } from "./one-time-card.js";
import { onrampRouter } from "./onramp.js";
import { unlock } from "./unlock.js";
import { getBalanceFields, getHeld, getPurchases } from "./wallet.js";

const PORT = 3000;
const BASE_SEPOLIA = "eip155:84532";

// createX402Server reads the three CDP_* env vars itself, and creates (or reuses)
// the "store-receiver" CDP account as the address that receives payments.
const x402Server = await createX402Server({
  environment: "development",
  payToConfig: { type: "eoa", accountName: "store-receiver" },
  routes: {
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
  },
});

const app = express();
app.use(express.urlencoded({ extended: false }));
app.use(express.json());
app.use(paymentMiddlewareFromHTTPServer(x402Server));

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

app.get("/api/items/market-report", (_req, res) => {
  res.json({
    item: "Market Report",
    generatedAt: new Date().toISOString(),
    summary: "Fake data: markets were mostly flat today.",
    highlights: [
      "Tech stocks rose 0.4%.",
      "Energy stocks fell 0.2%.",
      "USDC held at $1.00.",
    ],
  });
});

// x402-protected: the payment middleware only lets this through after the fee is paid.
app.get(UNLOCK_FEE.path, (_req, res) => {
  res.json({ ok: true });
});

// Called by the iOS app. Not x402-protected; the server pays the unlock fee itself.
app.post("/api/unlock", async (_req, res) => {
  const result = await unlock();
  res.status(result.status).json(result.body);
});

app.use("/api/onramp", onrampRouter);

app.get("/api/wallet", async (_req, res) => {
  const balanceFields = await getBalanceFields();
  res
    .status(balanceFields.balance === null ? 503 : 200)
    .json({ ...balanceFields, held: getHeld(), purchases: getPurchases() });
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

app.listen(PORT, () => {
  console.log(`Store running at http://localhost:${PORT}`);
  console.log(`x402 payments go to "store-receiver": ${x402Server.payToEvmAddress}`);
});

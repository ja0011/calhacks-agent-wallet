// Fake store with one x402-protected API route, based on Coinbase's seller quickstart:
// https://docs.cdp.coinbase.com/x402/seller/quickstart
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import express from "express";
import { createX402Server } from "@coinbase/cdp-sdk/x402";
import { paymentMiddlewareFromHTTPServer } from "@x402/express";

// Load CDP_API_KEY_ID, CDP_API_KEY_SECRET, CDP_WALLET_SECRET from server/.env,
// regardless of the directory the script is launched from.
dotenv.config({
  path: fileURLToPath(new URL("../.env", import.meta.url)),
  quiet: true,
});

const PORT = 3000;
const BASE_SEPOLIA = "eip155:84532";

// createX402Server reads the three CDP_* env vars itself, and creates (or reuses)
// the "store-receiver" CDP account as the address that receives payments.
const x402Server = await createX402Server({
  environment: "development",
  payToConfig: { type: "eoa", accountName: "store-receiver" },
  routes: {
    "GET /api/items/market-report": {
      price: "$0.01",
      networks: [BASE_SEPOLIA],
      description: "Market Report",
    },
  },
});

const app = express();
app.use(express.urlencoded({ extended: false }));
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
  res.send(
    page(
      "Fake Store",
      `<h1>Fake Store</h1>
<div class="item" id="market-report">
  <h2>Market Report</h2>
  <p class="price">$0.01</p>
  <p class="muted">Paid with x402 (USDC on Base Sepolia).
    Endpoint: <code>GET /api/items/market-report</code></p>
</div>
<div class="item" id="sneakers">
  <h2>Sneakers</h2>
  <p class="price">$59.00</p>
  <p class="muted">Paid with the card checkout form.</p>
  <a class="button" href="/checkout">Buy Sneakers</a>
</div>`,
    ),
  );
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

app.get("/checkout", (_req, res) => {
  res.send(
    page(
      "Checkout - Sneakers",
      `<h1>Checkout</h1>
<p>Item: <strong>Sneakers</strong>, total <strong>$59.00</strong></p>
<form method="post" action="/api/checkout">
  <input type="hidden" name="item" value="sneakers">

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

app.post("/api/checkout", (req, res) => {
  // TODO: verify the card with a real payment processor. For now any input is accepted,
  // and card details are never logged or stored.
  const name = typeof req.body?.name === "string" ? req.body.name : "";
  res.send(
    page(
      "Payment successful",
      `<h1>Payment successful</h1>
<p>Thanks${name ? `, ${escapeHtml(name)}` : ""}! Your order for <strong>Sneakers</strong> ($59.00) is confirmed.</p>
<p><a href="/">Back to store</a></p>`,
    ),
  );
});

app.listen(PORT, () => {
  console.log(`Store running at http://localhost:${PORT}`);
  console.log(`x402 payments go to "store-receiver": ${x402Server.payToEvmAddress}`);
});

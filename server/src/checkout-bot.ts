// Fills the store's checkout form in a visible Chromium window, like a person would.
// Never log `card`: it holds the full card number and CVC.
import { chromium } from "playwright";
import { STORE_URL } from "./catalog.js";

type CardDetails = { name: string; number: string; expiry: string; cvc: string };

// How long the result page stays on screen before the browser closes.
const RESULT_VISIBLE_MS = 3000;

export async function fillCheckout(itemId: string, card: CardDetails) {
  const browser = await chromium.launch({ headless: false, slowMo: 150 });
  try {
    const page = await browser.newPage();
    await page.goto(`${STORE_URL}/checkout?item=${encodeURIComponent(itemId)}`);
    await page.fill("#name", card.name);
    await page.fill("#card-number", card.number);
    await page.fill("#expiry", card.expiry);
    await page.fill("#cvc", card.cvc);
    await Promise.all([page.waitForURL("**/api/checkout"), page.click("button[type=submit]")]);
    await page.waitForTimeout(RESULT_VISIBLE_MS);
  } finally {
    await browser.close();
  }
}

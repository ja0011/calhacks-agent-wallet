// One-time virtual cards from Stripe Issuing (test mode). Full card details live only
// in this module's memory: never log them, return them to the agent, or send them to
// any client other than the checkout form filled by checkout-bot.ts.
import Stripe from "stripe";
import { findItem, formatUsd, type Item } from "./catalog.js";
import { fillCheckout } from "./checkout-bot.js";
import { getOnchainUsdcCents, recordPurchase } from "./wallet.js";

type Outcome = "pending" | "approved" | "declined";

type CardRecord = {
  cardId: string;
  itemId: string;
  priceCents: number;
  last4: string;
  brand: string;
  cardholderName: string;
  // Secret fields, cleared after the checkout attempt.
  number: string;
  expiry: string; // MM/YY, as typed into the checkout form
  cvc: string;
  outcome: Outcome;
  declineReason?: string;
};

class CardFlowError extends Error {}

const cardsById = new Map<string, CardRecord>();
const cardIdsByNumber = new Map<string, string>();
let lastUsedCardId: string | undefined;

// The API version the Dashboard used when it accepted financial_account_v2 on card creation.
// The SDK types only allow its own pinned version, so this is typed as a plain string and cast.
const STRIPE_API_VERSION: string = "2025-06-30.basil";
type StripeConfig = NonNullable<ConstructorParameters<typeof Stripe>[1]>;

let stripe: Stripe | undefined;
function getStripe() {
  if (!stripe) {
    const key = process.env.STRIPE_SECRET_KEY;
    if (!key) throw new CardFlowError("STRIPE_SECRET_KEY is not set in server/.env.");
    if (!/^(sk|rk)_test_/.test(key)) throw new CardFlowError("STRIPE_SECRET_KEY must be a test-mode key.");
    stripe = new Stripe(key, { apiVersion: STRIPE_API_VERSION as StripeConfig["apiVersion"] });
  }
  return stripe;
}

async function findCardholder() {
  const id = process.env.STRIPE_CARDHOLDER_ID;
  if (id) return getStripe().issuing.cardholders.retrieve(id);
  const { data } = await getStripe().issuing.cardholders.list({ status: "active", limit: 1 });
  if (!data[0]) {
    throw new CardFlowError("No active Issuing cardholder found. Create one in the Stripe dashboard or set STRIPE_CARDHOLDER_ID.");
  }
  return data[0];
}

// The v2 financial account (fa_test_...) that funds the cards.
function getFinancialAccountId() {
  const id = process.env.STRIPE_FINANCIAL_ACCOUNT_ID;
  if (!id) throw new CardFlowError("STRIPE_FINANCIAL_ACCOUNT_ID is not set in server/.env.");
  return id;
}

// financial_account_v2 isn't in the SDK's CardCreateParams type, but the API accepts it
// at STRIPE_API_VERSION (it's what the Dashboard sends), so it's added through this type.
type CardCreateParamsV2 = Stripe.Issuing.CardCreateParams & { financial_account_v2: string };

async function issueCard(item: Item): Promise<CardRecord> {
  const financialAccountId = getFinancialAccountId();
  const cardholder = await findCardholder();
  const params: CardCreateParamsV2 = {
    cardholder: cardholder.id,
    currency: "usd",
    type: "virtual",
    status: "active",
    financial_account_v2: financialAccountId,
    spending_controls: {
      spending_limits: [{ amount: item.priceCents, interval: "per_authorization" }],
    },
    metadata: { item: item.id },
  };
  const created = await getStripe().issuing.cards.create(params);

  // number and cvc are only returned by "Retrieve a card" with expand.
  const card = await getStripe().issuing.cards.retrieve(created.id, { expand: ["number", "cvc"] });
  if (!card.number || !card.cvc) throw new CardFlowError("Stripe did not return the card details.");

  const record: CardRecord = {
    cardId: card.id,
    itemId: item.id,
    priceCents: item.priceCents,
    last4: card.last4,
    brand: card.brand,
    cardholderName: cardholder.name,
    number: card.number,
    expiry: `${String(card.exp_month).padStart(2, "0")}/${String(card.exp_year % 100).padStart(2, "0")}`,
    cvc: card.cvc,
    outcome: "pending",
  };
  cardsById.set(record.cardId, record);
  cardIdsByNumber.set(record.number, record.cardId);
  return record;
}

function clearSecrets(record: CardRecord) {
  cardIdsByNumber.delete(record.number);
  record.number = "";
  record.cvc = "";
  record.expiry = "";
}

const cancelCard = (cardId: string) => getStripe().issuing.cards.update(cardId, { status: "canceled" });

// Only Stripe's and this module's error messages are passed on; anything else (e.g. a
// Playwright error) could echo what was typed into the form, so it gets a generic message.
const safeErrorMessage = (error: unknown) =>
  error instanceof Stripe.errors.StripeError || error instanceof CardFlowError ? error.message : "checkout failed";

// Called by the agent tool. Returns only last4, brand, and the outcome.
export async function buyWithOneTimeCard(itemId: unknown) {
  const item = typeof itemId === "string" ? findItem(itemId) : undefined;
  if (!item) return { ok: false, error: `Unknown item id: ${String(itemId)}` };
  if (item.method !== "card") return { ok: false, error: `${item.name} cannot be bought with a card.` };
  const balanceCents = await getOnchainUsdcCents();
  if (item.priceCents > balanceCents) {
    return { ok: false, error: `Insufficient balance: ${formatUsd(balanceCents)} available, ${formatUsd(item.priceCents)} needed.` };
  }

  let record: CardRecord | undefined;
  try {
    record = await issueCard(item);
    await fillCheckout(item.id, {
      name: record.cardholderName,
      number: record.number,
      expiry: record.expiry,
      cvc: record.cvc,
    });
  } catch (error) {
    console.error("One-time card purchase failed:", safeErrorMessage(error));
    return { ok: false, last4: record?.last4, brand: record?.brand, outcome: "error", error: safeErrorMessage(error) };
  } finally {
    if (record) {
      clearSecrets(record);
      if (record.outcome !== "approved") await cancelCard(record.cardId).catch(() => {});
    }
  }

  return {
    ok: record.outcome === "approved",
    last4: record.last4,
    brand: record.brand,
    outcome: record.outcome === "pending" ? "error" : record.outcome,
    ...(record.declineReason ? { declineReason: record.declineReason } : {}),
  };
}

type CheckoutInput = { number: string; expiry: string; cvc: string; itemId: string };

// Called by the store's POST /api/checkout with the submitted form fields.
export async function chargeAtCheckout({ number, expiry, cvc, itemId }: CheckoutInput) {
  const cardId = cardIdsByNumber.get(number.replace(/\s/g, ""));
  const record = cardId ? cardsById.get(cardId) : undefined;
  const item = findItem(itemId);
  if (!record || !item || record.itemId !== item.id) {
    return { approved: false, reason: "card_not_recognized" };
  }
  if (record.expiry !== expiry.trim() || record.cvc !== cvc.trim()) {
    record.outcome = "declined";
    record.declineReason = "verification_failed";
    return { approved: false, reason: record.declineReason };
  }

  // This stands in for the card network: Stripe test-mode Issuing cards only work inside
  // this Stripe account, so the store charges the card with Stripe's test-helper
  // authorization API instead of a real payment processor.
  const authorization = await getStripe().testHelpers.issuing.authorizations.create({
    card: record.cardId,
    amount: item.priceCents,
    currency: "usd",
    merchant_data: { name: "Fake Store" },
  });
  if (!authorization.approved) {
    record.outcome = "declined";
    record.declineReason = authorization.request_history.at(-1)?.reason ?? "declined";
    return { approved: false, reason: record.declineReason };
  }
  await getStripe().testHelpers.issuing.authorizations.capture(authorization.id);
  await cancelCard(record.cardId);

  // The USDC funding of this card is simulated: Stripe charges its own test-mode balance,
  // and no USDC moves on-chain, so the on-chain balance doesn't drop for card purchases.
  recordPurchase({ item: item.name, amount: formatUsd(item.priceCents), method: "One-time card" });
  record.outcome = "approved";
  lastUsedCardId = record.cardId;
  return { approved: true, item: item.name, amount: formatUsd(item.priceCents) };
}

// For the demo: charge the last used (now cancelled) card again to show it declining.
export async function retryLastCard() {
  const record = lastUsedCardId ? cardsById.get(lastUsedCardId) : undefined;
  if (!record) return { ok: false, error: "No one-time card has been used yet." };
  try {
    const authorization = await getStripe().testHelpers.issuing.authorizations.create({
      card: record.cardId,
      amount: record.priceCents,
      currency: "usd",
      merchant_data: { name: "Fake Store" },
    });
    return {
      ok: true,
      last4: record.last4,
      amount: formatUsd(record.priceCents),
      approved: authorization.approved,
      status: authorization.status,
      declineReason: authorization.request_history.at(-1)?.reason ?? null,
    };
  } catch (error) {
    // Stripe may reject the request outright instead of returning a declined authorization.
    return {
      ok: true,
      last4: record.last4,
      amount: formatUsd(record.priceCents),
      approved: false,
      declineReason: safeErrorMessage(error),
    };
  }
}

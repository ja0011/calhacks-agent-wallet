// AI shopping agent: a Claude tool-use loop that can list store items, pay for x402
// items with the CDP buyer wallet, and pay for card items with a one-time Stripe card.
import Anthropic from "@anthropic-ai/sdk";
import { SpendControlError } from "@coinbase/cdp-sdk/x402";
import { ITEMS, STORE_URL, findItem, formatUsd } from "./catalog.js";
import { buyWithOneTimeCard } from "./one-time-card.js";
import {
  fetchWithPayment,
  getBalance,
  getBalanceFields,
  getHeld,
  getOnchainUsdcCents,
  getPurchases,
  invalidateBalanceCache,
  recordPurchase,
} from "./wallet.js";

const MODEL = "claude-sonnet-5-5";
const MAX_TURNS = 10;

let anthropic: Anthropic | undefined;
const getAnthropic = () => (anthropic ??= new Anthropic());

const tools: Anthropic.Tool[] = [
  {
    name: "list_items",
    description:
      "Lists every item in the store with its id, name, price in USD, and payment method. " +
      'Items with method "x402" are bought with buy_with_x402; items with method "card" need a card checkout. ' +
      "Call this before buying so you use a valid item id and know the price.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "buy_with_x402",
    description:
      'Buys one store item whose payment method is "x402", paying in USDC from the agent wallet on Base Sepolia. ' +
      "Returns the item content on success. Payments over $0.10 each, or over $1.00 total this session, are refused. " +
      "Only call this when the user asked to buy the item.",
    input_schema: {
      type: "object",
      properties: {
        item_id: { type: "string", description: 'The item id from list_items, e.g. "market-report".' },
      },
      required: ["item_id"],
    },
  },
  {
    name: "get_balance",
    description: "Returns the agent wallet's current USDC balance in USD.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "buy_with_one_time_card",
    description:
      'Buys one store item whose payment method is "card". Issues a single-use virtual card limited to the item price, ' +
      "fills in the store's checkout form in a browser, and cancels the card afterwards. The price comes out of the " +
      "wallet balance. Returns the card's last 4 digits, brand, and the outcome (approved, declined, or error); " +
      "you never see the full card number. Only call this when the user asked to buy the item.",
    input_schema: {
      type: "object",
      properties: {
        item_id: { type: "string", description: 'The item id from list_items, e.g. "sticker-pack".' },
      },
      required: ["item_id"],
    },
  },
];

async function buyWithX402(itemId: unknown) {
  const item = typeof itemId === "string" ? findItem(itemId) : undefined;
  if (!item) return { ok: false, error: `Unknown item id: ${String(itemId)}` };
  if (item.method !== "x402") {
    return { ok: false, error: `${item.name} cannot be bought with x402.` };
  }
  const balanceCents = await getOnchainUsdcCents();
  if (item.priceCents > balanceCents) {
    return { ok: false, error: `Insufficient balance: ${formatUsd(balanceCents)} available, ${formatUsd(item.priceCents)} needed.` };
  }

  try {
    const response = await fetchWithPayment(`${STORE_URL}${item.path}`);
    if (!response.ok) {
      return { ok: false, error: `Store returned HTTP ${response.status}.` };
    }
    const content = await response.json();
    // The payment moved real USDC, so the on-chain balance drops by itself.
    invalidateBalanceCache();
    recordPurchase({ item: item.name, amount: formatUsd(item.priceCents), method: "x402" });
    return { ok: true, item: item.name, paid: formatUsd(item.priceCents), content };
  } catch (error) {
    if (error instanceof SpendControlError) {
      return { ok: false, error: `Blocked by spend controls (${error.code}): ${error.message}` };
    }
    throw error;
  }
}

async function runTool(name: string, input: Record<string, unknown>) {
  switch (name) {
    case "list_items":
      return ITEMS.map(({ id, name, priceCents, method }) => ({ id, name, price: formatUsd(priceCents), method }));
    case "buy_with_x402":
      return buyWithX402(input.item_id);
    case "get_balance":
      return { balance: await getBalance(), source: "onchain USDC on Base Sepolia" };
    case "buy_with_one_time_card":
      return buyWithOneTimeCard(input.item_id);
    default:
      return { ok: false, error: `Unknown tool: ${name}` };
  }
}

export async function runAgent(message: string) {
  const messages: Anthropic.MessageParam[] = [{ role: "user", content: message }];

  for (let turn = 0; turn < MAX_TURNS; turn++) {
    const response = await getAnthropic().messages.create({
      model: MODEL,
      max_tokens: 8000,
      system:
        "You are a shopping agent for a small online store. Use the tools to look up items, " +
        "check the wallet balance, and buy what the user asks for. Never buy anything the user " +
        'did not ask for. Prefer x402: if an item\'s method is "x402", use buy_with_x402. Use ' +
        'buy_with_one_time_card only for items whose method is "card". Keep replies short and ' +
        "say what was bought, for how much, and how it was paid.",
      tools,
      messages,
    });
    messages.push({ role: "assistant", content: response.content });

    if (response.stop_reason !== "tool_use") {
      const reply = response.content
        .filter((block): block is Anthropic.TextBlock => block.type === "text")
        .map((block) => block.text)
        .join("\n");
      return { reply, ...(await getBalanceFields()), held: getHeld(), purchases: getPurchases() };
    }

    const results: Anthropic.ToolResultBlockParam[] = [];
    for (const block of response.content) {
      if (block.type !== "tool_use") continue;
      try {
        const output = await runTool(block.name, block.input as Record<string, unknown>);
        results.push({ type: "tool_result", tool_use_id: block.id, content: JSON.stringify(output) });
      } catch (error) {
        const detail = error instanceof Error ? error.message : "unknown error";
        results.push({ type: "tool_result", tool_use_id: block.id, content: `Tool failed: ${detail}`, is_error: true });
      }
    }
    messages.push({ role: "user", content: results });
  }

  return {
    reply: "Stopped: the agent used too many steps without finishing.",
    ...(await getBalanceFields()),
    held: getHeld(),
    purchases: getPurchases(),
  };
}

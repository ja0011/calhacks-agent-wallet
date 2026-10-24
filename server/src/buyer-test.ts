// Minimal x402 buyer test, based on Coinbase's buyer quickstart:
// https://docs.cdp.coinbase.com/x402/quickstart-for-buyers
import { fileURLToPath } from "node:url";
import dotenv from "dotenv";
import { CdpX402Client } from "@coinbase/cdp-sdk/x402";
import { wrapFetchWithPayment } from "@x402/fetch";

// Load CDP_API_KEY_ID, CDP_API_KEY_SECRET, CDP_WALLET_SECRET from server/.env,
// regardless of the directory the script is launched from.
dotenv.config({
  path: fileURLToPath(new URL("../.env", import.meta.url)),
  quiet: true,
});

// CdpX402Client reads the three CDP_* env vars itself.
// "development" = Base Sepolia testnet; omit it for Base mainnet.
const client = new CdpX402Client({ environment: "development" });

// The wallet is CDP-managed; print its public address so it can be funded.
const { evmAddress } = await client.getAddresses();
console.log(`Paying from ${evmAddress}`);

// Wrapped fetch handles the 402 response, signs the payment, and retries.
const fetchWithPayment = wrapFetchWithPayment(globalThis.fetch, client);
const response = await fetchWithPayment("https://x402.vercel.app/protected");

console.log(`HTTP ${response.status}`);
console.log(await response.text());

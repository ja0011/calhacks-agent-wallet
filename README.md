# calhacks-agent-wallet

# Spendy

Spendy locks the apps you can't put down. To open one, you pay. The money funds an AI agent that shops for you.

Built solo at Cal Hacks 13.0. Everything runs in test mode on Base Sepolia.

## How it works

1. **Lock.** The iOS app uses Apple's Screen Time (FamilyControls, ManagedSettings) to shield chosen apps. A DeviceActivity extension re-locks them when the unlock window ends.
2. **Unlock.** You pay by card in Crossmint's checkout, which delivers USDC to a Coinbase CDP wallet. The wallet then pays the unlock over x402, and the apps open for 15 minutes.
3. **Shop.** A Claude agent (Anthropic API) buys from merchants. It pays with x402 where a merchant supports it, and with a one-time Stripe Issuing virtual card, capped at the price and cancelled after one use, where it doesn't. Spend limits are enforced in code, and Claude never sees card numbers or keys.

## What's real and what's simulated

Real, in test mode: x402 payments on Base Sepolia, the on-chain USDC balance, the Crossmint card purchase, Stripe card creation and decline, the Screen Time lock.

Simulated and labeled in the app: the bank balance, the two-week time vault, and funding the card from USDC.

## Stack

SwiftUI, TypeScript, Node, Express, Coinbase CDP SDK and x402, Crossmint onramp, Stripe Issuing, Anthropic API, Playwright, viem.

## Run it

Needs Node 24, Xcode, and an iPhone (Screen Time doesn't work in the simulator). Copy `server/.env.example` to `server/.env` and add your own keys: CDP, Crossmint (staging), Stripe (test), Anthropic.

    cd server
    npm install
    npx playwright install chromium
    npm run store

Expose it with `cloudflared tunnel --url http://localhost:3000`, put the address in `ios/Agentwallet/Agentwallet/Config.swift`, and run the app on your iPhone from Xcode.

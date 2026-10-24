# Agentwallet (iOS)

SwiftUI client for the local agent-wallet server.

## Conventions
- SwiftUI only, MVVM, Swift concurrency (async/await). No Combine. The only third-party package is Crossmint's `CrossmintCheckout` (from `crossmint-checkout-swift`), used by `Views/OnrampCheckoutView.swift` for the "Add money" onramp.
- iOS 17+ APIs (`@Observable`, `@Environment(Type.self)`).
- Layout under `Agentwallet/`:
  - `Models/` — Codable types (`ChatMessage`, `Purchase`, `ChatResponse`).
  - `Services/APIClient.swift` — URLSession networking. Only `POST /api/chat` for now.
  - `ViewModels/ChatViewModel.swift` — shared chat view model (messages, balance, purchases), injected once in `AgentwalletApp` via `.environment` and read by both tabs.
  - `Views/` — `ChatView`, `WalletView`. `ContentView` is the root `TabView`.
  - `Config.swift` — `Config.serverURL` (`http://localhost:3000`). Never hardcode URLs elsewhere.
- **No API keys or secrets in the app.** The app only talks to our server; the server holds all credentials.
- ATS: only `NSAppTransportSecurity > NSAllowsLocalNetworking = YES` in `Agentwallet/Info.plist`. Do not add `NSAllowsArbitraryLoads`.
- Screen Time lock (Unlock tab): `ViewModels/LockViewModel.swift` (separate from `ChatViewModel`), `Services/ShieldService.swift` (`ManagedSettingsStore` + saved `FamilyActivitySelection`), `Views/UnlockView.swift`. Entitlement `com.apple.developer.family-controls`, authorization `.individual`. Unlock = `POST Config.unlockURL`; only HTTP 200 lifts the shield, for `Config.unlockDuration` (15 min).
- Re-lock: on unlock, `Services/RelockScheduler.swift` starts a 15-min DeviceActivity window (`LockShared.unlockWindowActivity`). The DeviceActivityMonitor extension's `intervalDidEnd` re-applies the shield. An in-app timer and a check when the app becomes active also re-lock while the app is open.
- `Services/LockShared.swift` and `Services/ShieldService.swift` are shared with the extension target (keep them `nonisolated`, with no app-only dependencies). The selection is stored in App Group `group.FB.Agentwallet`.
- Don't edit signing, entitlements, or capabilities from code; the user manages them in Xcode.
- Build with Xcode and run on an iPhone simulator. Fix build errors before calling a task done.

## Server API
`POST /api/chat` `{ "message": String }` →
`{ "reply": String, "balance": "$0.99", "purchases": [{ "item", "amount", "method" }] }`
(`method` is `"x402"` or `"One-time card"`).

`POST /api/unlock` → HTTP 200 means approved; any other status means denied.

`GET /api/wallet` → `{ "balance", "held", "purchases" }`.

Onramp ("Add money" on the Wallet tab, `ViewModels/OnrampViewModel.swift`):
`POST /api/onramp/link-wallet`, then `POST /api/onramp/order` `{ "amount": "5" }` → `{ orderId, clientSecret, quote, paymentStatus }`,
then `GET /api/onramp/config` → `{ clientApiKey, environment }` (publishable `ck_staging_` key; it selects the Crossmint environment).
After checkout, poll `GET /api/onramp/order/<orderId>` → `{ paymentStatus, deliveryStatus, txId }` until `deliveryStatus == "completed"`.

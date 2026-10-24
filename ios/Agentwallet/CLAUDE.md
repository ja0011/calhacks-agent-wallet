# Agentwallet (iOS)

SwiftUI client for the local agent-wallet server.

## Conventions
- SwiftUI only, MVVM, Swift concurrency (async/await). No Combine, no third-party packages.
- iOS 17+ APIs (`@Observable`, `@Environment(Type.self)`).
- Layout under `Agentwallet/`:
  - `Models/` — Codable types (`ChatMessage`, `Purchase`, `ChatResponse`).
  - `Services/APIClient.swift` — URLSession networking. Only `POST /api/chat` for now.
  - `ViewModels/ChatViewModel.swift` — single shared view model (messages, balance, purchases), injected once in `AgentwalletApp` via `.environment` and read by both tabs.
  - `Views/` — `ChatView`, `WalletView`. `ContentView` is the root `TabView`.
  - `Config.swift` — `Config.serverURL` (`http://localhost:3000`). Never hardcode URLs elsewhere.
- **No API keys or secrets in the app.** The app only talks to our server; the server holds all credentials.
- ATS: only `NSAppTransportSecurity > NSAllowsLocalNetworking = YES` in `Agentwallet/Info.plist`. Do not add `NSAllowsArbitraryLoads`.
- Screen Time / Family Controls are not in the app yet. Don't add them unless asked.
- Build with Xcode and run on an iPhone simulator. Fix build errors before calling a task done.

## Server API
`POST /api/chat` `{ "message": String }` →
`{ "reply": String, "balance": "$0.99", "purchases": [{ "item", "amount", "method" }] }`
(`method` is `"x402"` or `"One-time card"`).

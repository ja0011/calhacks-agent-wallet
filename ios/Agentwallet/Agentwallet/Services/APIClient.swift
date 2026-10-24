//
//  APIClient.swift
//  Agentwallet
//

import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .badStatus(let code):
            return "Server returned status \(code)."
        }
    }
}

/// Thin async/await wrapper around URLSession for talking to the agent server.
struct APIClient {
    var baseURL: String = Config.serverURL
    var session: URLSession = .shared

    /// POST /api/chat with `{ "message": ... }` and decode the reply.
    func sendChat(message: String) async throws -> ChatResponse {
        guard let url = URL(string: baseURL)?.appending(path: "api/chat") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(message: message))

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }

        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    /// GET /api/wallet: the current balance and purchases.
    func fetchWallet() async throws -> WalletResponse {
        try await send(method: "GET", path: "api/wallet")
    }

    /// POST /api/onramp/link-wallet: links the buyer wallet to the Crossmint user.
    func linkOnrampWallet() async throws {
        _ = try await data(method: "POST", path: "api/onramp/link-wallet")
    }

    /// POST /api/onramp/order with `{ "amount": ... }`.
    func createOnrampOrder(amount: String) async throws -> OnrampOrder {
        try await send(
            method: "POST",
            path: "api/onramp/order",
            body: try JSONEncoder().encode(OnrampOrderRequest(amount: amount))
        )
    }

    /// GET /api/onramp/config: the publishable Crossmint client key.
    func fetchOnrampConfig() async throws -> OnrampConfig {
        try await send(method: "GET", path: "api/onramp/config")
    }

    /// GET /api/onramp/order/:orderId: payment and delivery status.
    func fetchOnrampOrderStatus(orderId: String) async throws -> OnrampOrderStatus {
        try await send(method: "GET", path: "api/onramp/order/\(orderId)")
    }

    /// Sends a request with an optional JSON body and decodes the JSON response.
    private func send<Response: Decodable>(method: String, path: String, body: Data? = nil) async throws -> Response {
        let data = try await data(method: method, path: path, body: body)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// Sends a request with an optional JSON body. Throws `APIError.badStatus` on non-2xx.
    private func data(method: String, path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseURL)?.appending(path: path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        return data
    }

    /// POST /api/unlock. Succeeds only on HTTP 200; any other status throws `APIError.badStatus`.
    func requestUnlock() async throws {
        guard let url = Config.unlockURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (_, response) = try await session.data(for: request)

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            throw APIError.badStatus(status)
        }
    }
}

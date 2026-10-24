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

//
//  Purchase.swift
//  Agentwallet
//

import Foundation

/// A purchase made by the agent, as returned by the server.
struct Purchase: Identifiable, Codable, Equatable {
    /// Local-only identifier; the server doesn't send one, so it's excluded from coding.
    var id = UUID()
    let item: String
    let amount: String
    /// Payment method, e.g. "x402" or "One-time card".
    let method: String

    private enum CodingKeys: String, CodingKey {
        case item, amount, method
    }
}

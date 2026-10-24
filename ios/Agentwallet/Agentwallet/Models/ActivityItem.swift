//
//  ActivityItem.swift
//  Agentwallet
//

import Foundation

/// One row of recent activity, from the optional "activity" array of GET /api/wallet.
struct ActivityItem: Identifiable, Codable, Equatable {
    /// Local-only identifier; the server doesn't send one, so it's excluded from coding.
    var id = UUID()
    let label: String
    /// e.g. "x402", "One-time card", "Card".
    let method: String
    let amount: String

    var direction: String? = nil
    var at: String? = nil

    var isIncoming: Bool { direction == "in" }

    var signedAmount: String {
        let magnitude = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        return (isIncoming ? "+" : "-") + magnitude
    }

    private enum CodingKeys: String, CodingKey {
        case label, method, amount, direction, at
    }
}

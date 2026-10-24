//
//  ChatResponse.swift
//  Agentwallet
//

import Foundation

/// Request body for POST /api/chat.
struct ChatRequest: Codable {
    let message: String
}

/// Response body for POST /api/chat.
struct ChatResponse: Codable {
    let reply: String
    /// Formatted balance, e.g. "$0.99".
    let balance: String?
    let bank: WalletResponse.Bank?
    let activity: [ActivityItem]?
    let purchases: [Purchase]
}

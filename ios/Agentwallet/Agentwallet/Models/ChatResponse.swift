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
    /// Formatted balance from the server.
    let balance: String?
    let bank: WalletResponse.Bank?
    let activity: [ActivityItem]?
    let purchases: [Purchase]
    var items: [CatalogItem]? = nil
}

 /// Catalog rows use the server's list_items representation.
struct CatalogItem: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let merchant: String?
    let price: String
    let method: String

    var purchasePrompt: String { "Buy " + name }
}

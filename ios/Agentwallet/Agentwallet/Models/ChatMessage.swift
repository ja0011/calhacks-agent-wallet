//
//  ChatMessage.swift
//  Agentwallet
//

import Foundation

/// A single message shown in the chat list.
struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case agent
        case error
    }

    var id = UUID()
    let role: Role
    let text: String
    var receipts: [Purchase] = []
}

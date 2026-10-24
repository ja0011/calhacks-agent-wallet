//
//  ChatViewModel.swift
//  Agentwallet
//

import Foundation
import Observation

/// Single source of truth shared by the Chat and Wallet tabs.
/// Holds the conversation plus the latest balance and purchases from the server.
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var draft: String = ""
    var isLoading = false

    var balance: String = "—"
    var purchases: [Purchase] = []

    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    var canSend: Bool {
        !isLoading && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await client.sendChat(message: text)
            messages.append(ChatMessage(role: .agent, text: response.reply))
            balance = response.balance
            purchases = response.purchases
        } catch {
            messages.append(ChatMessage(role: .error, text: "Request failed: \(error.localizedDescription)"))
        }
    }

    /// Reloads the balance and purchases from GET /api/wallet.
    func refreshWallet() async {
        guard let wallet = try? await client.fetchWallet() else { return }
        balance = wallet.balance
        purchases = wallet.purchases
    }
}

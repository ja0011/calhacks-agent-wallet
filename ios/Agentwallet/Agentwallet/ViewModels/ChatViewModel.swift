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
    var purchases: [Purchase] = [] { didSet { rebuildHistory() } }
    /// "bank.balance" from GET /api/wallet; nil if the server doesn't send it.
    var unlockPriceText: String?
    var limits: WalletResponse.Limits?
    var bankBalance: String?
    /// "activity" from GET /api/wallet; nil if the server doesn't send it.
    var activity: [ActivityItem]? { didSet { rebuildHistory() } }
    private(set) var history: [ActivityItem] = []
    @ObservationIgnored private var settlementTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    var isRefreshingWallet = false
    var walletError: String?

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
            refreshGeneration += 1
            balance = response.balance ?? "—"
            bankBalance = response.bank?.balance
            purchases = response.purchases
            activity = response.activity
            await refreshAfterMoneyMovement()
        } catch {
            messages.append(ChatMessage(role: .error, text: "Request failed: \(error.localizedDescription)"))
        }
    }

    var recentActivity: [ActivityItem] { Array(history.prefix(3)) }

    private func rebuildHistory() {
        // Activity is newest-first; legacy purchases are oldest-first.
        let items = activity ?? purchases.reversed().map {
            ActivityItem(id: $0.id, label: $0.item, method: $0.method, amount: $0.amount, direction: "out")
        }
        // Preserve row identities across refreshes, including duplicate entries.
        var previous = history
        history = items.map { item in
            var item = item
            if let index = previous.firstIndex(where: {
                $0.label == item.label && $0.method == item.method && $0.amount == item.amount
                    && $0.direction == item.direction && $0.at == item.at
            }) {
                item.id = previous.remove(at: index).id
            }
            return item
        }
    }

    func applyUnlock(_ response: UnlockResponse) {
        refreshGeneration += 1
        balance = response.balance ?? "—"
        if let bank = response.bank { bankBalance = bank.balance }
        if let activity = response.activity { self.activity = activity }
    }

    /// Refresh immediately, then once more after Base has had time to settle.
    /// Owned by the model so changing tabs doesn't cancel the delayed refresh.
    func refreshAfterMoneyMovement() async {
        settlementTask?.cancel()
        settlementTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await self?.refreshWallet()
        }
        await refreshWallet()
    }

    /// Reloads the balance, bank, activity, and purchases from GET /api/wallet.
    /// On failure, keeps the last values and sets `walletError`.
    func refreshWallet() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshingWallet = true
        defer { if generation == refreshGeneration { isRefreshingWallet = false } }

        do {
            let wallet = try await client.fetchWallet()
            guard generation == refreshGeneration else { return }
            unlockPriceText = wallet.unlockPriceText
            limits = wallet.limits
            balance = wallet.balance ?? "—"
            bankBalance = wallet.bank?.balance
            activity = wallet.activity
            purchases = wallet.purchases
            walletError = nil
        } catch {
            guard generation == refreshGeneration else { return }
            walletError = "Couldn't update: \(error.localizedDescription)"
        }
    }
}

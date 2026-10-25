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
    private(set) var catalogItems: [CatalogItem] = []

    var balance: String = "—"
    var purchases: [Purchase] = [] { didSet { rebuildHistory() } }
    /// "bank.balance" from GET /api/wallet; nil if the server doesn't send it.
    var unlockPriceText: String?
    var limits: WalletResponse.Limits?
    var bankBalance: String?
    var walletAddress: String?
    var vault: TimeVault?
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

    func send(suggestion: String? = nil) async {
        let text = (suggestion ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        if suggestion == nil { draft = "" }
        messages.append(ChatMessage(role: .user, text: text))
        isLoading = true
        defer { isLoading = false }

        do {
            // The server returns cumulative purchases without transaction IDs.
            // A fresh baseline prevents historical purchases becoming new receipts.
            let baseline = try? await client.fetchWallet().purchases
            let response = try await client.sendChat(message: text)
            let receipts = baseline.map { Self.newPurchases(response.purchases, since: $0) } ?? []
            messages.append(ChatMessage(role: .agent, text: response.reply, receipts: receipts))
            if baseline == nil && !response.purchases.isEmpty {
                messages.append(ChatMessage(role: .error, text: "Receipt details couldn't be verified. Check your wallet history before retrying a purchase."))
            }
            refreshGeneration += 1
            if let items = response.items { catalogItems = items }
            balance = response.balance ?? "—"
            bankBalance = response.bank?.balance
            purchases = response.purchases
            activity = response.activity
            await refreshAfterMoneyMovement()
        } catch {
            messages.append(ChatMessage(role: .error, text: "Request failed: \(error.localizedDescription)"))
        }
    }

    /// Multiset subtraction handles repeated purchases with identical names and amounts.
    static func newPurchases(_ purchases: [Purchase], since baseline: [Purchase]) -> [Purchase] {
        var remaining = baseline
        return purchases.filter { purchase in
            if let index = remaining.firstIndex(where: {
                $0.item == purchase.item && $0.amount == purchase.amount && $0.method == purchase.method
            }) {
                remaining.remove(at: index)
                return false
            }
            return true
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
            catalogItems = wallet.items ?? []
            vault = wallet.vault
            walletAddress = wallet.walletAddress
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

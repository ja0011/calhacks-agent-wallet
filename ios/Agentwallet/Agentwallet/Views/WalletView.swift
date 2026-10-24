//
//  WalletView.swift
//  Agentwallet
//

import SwiftUI

struct WalletView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var onramp = OnrampViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MoneyRow(icon: "building.columns.fill", title: "Bank", subtitle: "Checking, simulated",
                             amount: viewModel.bankBalance ?? "-")
                    MoneyRow(icon: "wallet.bifold.fill", title: "USDC wallet", subtitle: "Base Sepolia testnet",
                             amount: viewModel.balance)
                }

                Section {
                    Button {
                        Task { await onramp.start() }
                    } label: {
                        HStack {
                            Label("Add money", systemImage: "plus.circle.fill")
                            Spacer()
                            if onramp.isBusy {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(onramp.isBusy)

                    OnrampStatusRow(status: onramp.status)
                } footer: {
                    Text("Buy $\(OnrampViewModel.amount) of testnet USDC on Base Sepolia by card (Crossmint staging).")
                }

                Section("Unlock") {
                    if let price = viewModel.unlockPriceText {
                        Text("Unlock price: \(price)")
                    } else {
                        Text("Unlock price unavailable")
                    }
                    WalletLimitsText()
                }

                Section("History") {
                    if viewModel.history.isEmpty {
                        Text("No activity yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.history) { item in
                            ActivityRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("Wallet")
            .task { await viewModel.refreshWallet() }
            .refreshable { await viewModel.refreshWallet() }
            .sheet(item: $onramp.session, onDismiss: {
                Task { await onramp.checkoutClosed(wallet: viewModel) }
            }) { session in
                OnrampCheckoutView(session: session) { phase, paymentStatus in
                    onramp.checkoutUpdated(phase: phase, paymentStatus: paymentStatus)
                }
            }
        }
    }
}

private struct OnrampStatusRow: View {
    let status: OnrampViewModel.Status

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .preparing:
            Text("Creating order…").foregroundStyle(.secondary)
        case .inCheckout:
            Text("Complete the checkout to add money.").foregroundStyle(.secondary)
        case .waitingForDelivery(let message):
            Text(message).foregroundStyle(.secondary)
        case .delivered(let txId):
            VStack(alignment: .leading, spacing: 4) {
                Label("USDC delivered", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let txId {
                    Text(txId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    WalletView()
        .environment(ChatViewModel())
}

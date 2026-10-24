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
                    VStack(spacing: 4) {
                        Text("Balance")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(viewModel.balance)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
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

                Section("Purchases") {
                    if viewModel.purchases.isEmpty {
                        Text("No purchases yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.purchases) { purchase in
                            PurchaseRow(purchase: purchase)
                        }
                    }
                }
            }
            .navigationTitle("Wallet")
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

private struct PurchaseRow: View {
    let purchase: Purchase

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(purchase.item)
                    .font(.headline)
                Text(purchase.method)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(methodColor.opacity(0.15), in: .capsule)
                    .foregroundStyle(methodColor)
            }
            Spacer()
            Text(purchase.amount)
                .font(.body.monospacedDigit())
        }
    }

    private var methodColor: Color {
        purchase.method == "x402" ? .purple : .blue
    }
}

#Preview {
    WalletView()
        .environment(ChatViewModel())
}

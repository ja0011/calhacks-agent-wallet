//
//  WalletView.swift
//  Agentwallet
//

import SwiftUI

struct WalletView: View {
    @Environment(ChatViewModel.self) private var viewModel

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

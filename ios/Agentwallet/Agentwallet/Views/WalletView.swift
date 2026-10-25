import SwiftUI
import UIKit

struct WalletView: View {
    @Environment(ChatViewModel.self) private var viewModel
    @State private var onramp = OnrampViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WalletRefreshStatus()
                    Card {
                        HomeMoneyRow(icon: "wallet.bifold.fill", title: "USDC wallet",
                                     subtitle: "Base Sepolia testnet", amount: viewModel.balance)
                        if let address = viewModel.walletAddress {
                            Divider()
                            WalletAddressRow(address: address)
                        }
                        Divider()
                        HomeMoneyRow(icon: "building.columns.fill", title: "Bank",
                                     subtitle: "Checking, simulated", amount: viewModel.bankBalance ?? "-")
                    }
                    WalletHistoryCard()
                    Card {
                        Text("Add money").font(.headline)
                        Button {
                            Task { await onramp.start() }
                        } label: {
                            HStack {
                                Label("Add money by card", systemImage: "plus.circle.fill")
                                if onramp.isBusy { ProgressView() }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(onramp.isBusy)
                        OnrampStatusRow(status: onramp.status)
                        Text("Card funding delivers testnet USDC on Base Sepolia through Crossmint staging. Review the amount in checkout.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let limits = viewModel.limits {
                        Text("Agent limits: \(limits.perPaymentText) per payment, \(limits.perSessionText) per session.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Agent limits unavailable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(SpendyHomeStyle.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                SpendyHeader()
            }
            .foregroundStyle(SpendyHomeStyle.ink)
            .tint(SpendyHomeStyle.orange)
            .environment(\.colorScheme, .light)
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

private struct WalletRefreshStatus: View {
    @Environment(ChatViewModel.self) private var wallet

    var body: some View {
        if wallet.isRefreshingWallet {
            HStack(spacing: 8) {
                ProgressView()
                Text("Updating wallet…").font(.subheadline)
            }
        }
        if let error = wallet.walletError {
            Card {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                Text("Previously loaded values may be out of date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await wallet.refreshWallet() } }
                    .buttonStyle(.bordered)
                    .disabled(wallet.isRefreshingWallet)
            }
        }
    }
}

private struct WalletAddressRow: View {
    let address: String
    @State private var copied = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallet address").font(.caption).foregroundStyle(.secondary)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Text(WalletAddressDisplay.shortened(address))
                    .font(.subheadline.monospaced())
                    .accessibilityLabel("Wallet address: " + address)
                Button {
                    UIPasteboard.general.string = address
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(copied ? "Wallet address copied" : "Copy full wallet address")
            }
            if let url = WalletAddressDisplay.explorerURL(address) {
                Link(destination: url) {
                    Label("View on explorer", systemImage: "arrow.up.right")
                }
                .font(.subheadline)
                .tint(SpendyHomeStyle.purple)
            }
        }
        .onChange(of: address) { copied = false }
    }
}

private struct WalletHistoryCard: View {
    @Environment(ChatViewModel.self) private var wallet

    var body: some View {
        Card {
            Text("History").font(.headline).accessibilityAddTraits(.isHeader)
            if wallet.history.isEmpty {
                Text(wallet.isRefreshingWallet ? "Loading activity…" :
                     wallet.walletError != nil ? "Activity unavailable. Try refreshing." : "No activity yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(wallet.history) { item in
                    HomeActivityRow(item: item)
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
    WalletView().environment(ChatViewModel())
}

#Preview("Wallet — larger text") {
    WalletView()
        .environment(ChatViewModel())
        .environment(\.dynamicTypeSize, .accessibility3)
}

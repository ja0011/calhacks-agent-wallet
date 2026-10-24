//
//  UnlockView.swift
//  Agentwallet
//

import FamilyControls
import SwiftUI

struct UnlockView: View {
    @Environment(LockViewModel.self) private var viewModel
    @Environment(ChatViewModel.self) private var wallet
    @State private var isPickerPresented = false

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            List {
                Section {
                    LockStatusView(state: viewModel.state)
                }

                if !viewModel.isAuthorized {
                    Section {
                        Text("Screen Time access is needed to lock apps.")
                            .foregroundStyle(.secondary)
                        Button("Allow Screen Time Access") {
                            Task { await viewModel.requestAuthorization() }
                        }
                    }
                }

                Section("Apps to lock") {
                    Button("Choose Apps…") { isPickerPresented = true }
                        .disabled(!viewModel.isAuthorized)
                    Text(selectionSummary)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Lock Now", systemImage: "lock.fill") {
                        viewModel.lockNow()
                    }
                    .disabled(!viewModel.isAuthorized || !viewModel.hasSelection || viewModel.state == .locked)

                    UnlockPaymentButtons()
                    WalletLimitsText()
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Unlock")
            .task { await wallet.refreshWallet() }
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $viewModel.selection)
            .onChange(of: viewModel.selection) {
                viewModel.selectionChanged()
            }
        }
    }

    private var selectionSummary: String {
        let apps = viewModel.selection.applicationTokens.count
        let categories = viewModel.selection.categoryTokens.count
        let sites = viewModel.selection.webDomainTokens.count
        if apps + categories + sites == 0 { return "Nothing selected" }
        return "\(apps) apps, \(categories) categories, \(sites) websites"
    }
}

/// Large lock indicator with a live countdown while temporarily unlocked.
private struct LockStatusView: View {
    let state: LockViewModel.LockState

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 56))
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(.title2.bold())

            if case .temporarilyUnlocked(let until) = state {
                // Redraws every second; the view model handles the actual re-lock.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, until.timeIntervalSince(context.date))
                    Text("Re-locks in \(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }

    private var iconName: String {
        state == .locked ? "lock.fill" : "lock.open.fill"
    }

    private var color: Color {
        switch state {
        case .locked: .red
        case .temporarilyUnlocked: .orange
        case .unlocked: .green
        }
    }

    private var title: String {
        switch state {
        case .locked: "Locked"
        case .temporarilyUnlocked: "Temporarily unlocked"
        case .unlocked: "Not locked"
        }
    }
}

#Preview {
    UnlockView()
        .environment(LockViewModel())
        .environment(ChatViewModel())
}

/// Shared actions keep Home and the Unlock tab on the same payment flow.
struct UnlockPaymentButtons: View {
    @Environment(LockViewModel.self) private var lock
    @Environment(ChatViewModel.self) private var wallet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await lock.startCardUnlock() }
            } label: {
                HStack {
                    if lock.isPaymentBusy { ProgressView() }
                    if let price = wallet.unlockPriceText {
                        Text("Unlock for \(price)")
                    } else {
                        Text("Unlock price unavailable")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(lock.state != .locked || lock.isPaymentBusy || wallet.unlockPriceText == nil)

            if let price = wallet.unlockPriceText {
                Text("You pay \(price) by card. Crossmint delivers it as USDC, and your wallet pays it over x402 to unlock your apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Unlock with wallet balance") {
                Task {
                    await lock.unlock(wallet: wallet)
                }
            }
            .font(.footnote)
            .buttonStyle(.borderless)
            .disabled(lock.state != .locked || lock.isPaymentBusy)

            switch lock.checkout.status {
            case .preparing:
                Text("Creating checkout…").font(.caption)
            case .inCheckout:
                Text("Complete the card checkout.").font(.caption)
            case .waitingForDelivery:
                Text("Waiting for USDC delivery. Apps stay locked.").font(.caption)
            case .failed:
                Text("Checkout or delivery was not confirmed. Apps stay locked.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            default:
                EmptyView()
            }
        }
    }
}

struct WalletLimitsText: View {
    @Environment(ChatViewModel.self) private var wallet

    var body: some View {
        if let limits = wallet.limits {
            Text("Agent limits: \(limits.perPaymentText) per payment, \(limits.perSessionText) per session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Agent limits unavailable.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

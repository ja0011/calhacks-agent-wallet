import FamilyControls
import ManagedSettings
import SwiftUI

struct UnlockView: View {
    @Environment(LockViewModel.self) private var viewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPickerPresented = false
    @State private var isRequestingAuthorization = false

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                        if !viewModel.isAuthorized {
                            Text("Allow Screen Time access to choose and lock apps.")
                                .foregroundStyle(.secondary)
                            Button {
                                guard !isRequestingAuthorization else { return }
                                isRequestingAuthorization = true
                                Task {
                                    await viewModel.requestAuthorization()
                                    isRequestingAuthorization = false
                                }
                            } label: {
                                HStack {
                                    if isRequestingAuthorization { ProgressView() }
                                    Text(viewModel.authorizationStatus == .denied ? "Request access again" : "Allow Screen Time access")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isRequestingAuthorization)
                        }
                    Card {
                        HStack(spacing: 12) {
                            HomeIconTile(symbol: "square.grid.2x2.fill")
                            Text("Apps to lock").font(.headline)
                        }
                        SelectedAppsSummary(selection: viewModel.selection)
                        if viewModel.hasSelection {
                            SelectedActivityList(selection: viewModel.selection)
                        }
                        Button {
                            isPickerPresented = true
                        } label: {
                            Label("Choose apps", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(SpendyHomeStyle.purple)
                        .disabled(!viewModel.isAuthorized || isRequestingAuthorization)
                        if !viewModel.hasSelection {
                            Text("Choose at least one app, category, or website to lock.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = viewModel.errorMessage {
                        Card {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
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
            .familyActivityPicker(isPresented: $isPickerPresented, selection: $viewModel.selection)
            .onChange(of: viewModel.selection) { viewModel.selectionChanged() }
            .onChange(of: scenePhase) {
                if scenePhase == .active { viewModel.refresh() }
            }
            .onAppear { viewModel.refresh() }
        }
    }

}

private struct SelectedAppsSummary: View {
    let selection: FamilyActivitySelection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(selection.applicationTokens.count) apps selected", systemImage: "app")
            Label("\(selection.categoryTokens.count) categories selected", systemImage: "square.stack")
            Label("\(selection.webDomainTokens.count) websites selected", systemImage: "globe")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

/// Tokens are opaque: system labels resolve their names and icons without exposing
/// that private information to the app. Keep plain text so a failed system label
/// never leaves an unidentifiable selection.
private struct SelectedActivityList: View {
    let selection: FamilyActivitySelection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(selection.applicationTokens.sorted { $0.hashValue < $1.hashValue }.enumerated(),
                    id: \.element) { index, token in
                SelectedActivityRow(fallback: "Selected app \(index + 1)") {
                    Label(token)
                }
            }
            if !selection.categoryTokens.isEmpty {
                Text("Categories").font(.subheadline.weight(.semibold))
                ForEach(selection.categoryTokens.sorted { $0.hashValue < $1.hashValue }.enumerated(),
                        id: \.element) { index, token in
                    SelectedActivityRow(fallback: "Selected category \(index + 1)") {
                        Label(token)
                    }
                }
            }
            if !selection.webDomainTokens.isEmpty {
                Text("Websites").font(.subheadline.weight(.semibold))
                ForEach(selection.webDomainTokens.sorted { $0.hashValue < $1.hashValue }.enumerated(),
                        id: \.element) { index, token in
                    SelectedActivityRow(fallback: "Selected website \(index + 1)") {
                        Label(token)
                    }
                }
            }
        }
    }
}

private struct SelectedActivityRow<Content: View>: View {
    let fallback: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .labelStyle(.titleAndIcon)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text(fallback)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    UnlockView().environment(LockViewModel())
}

#Preview("App locking — larger text") {
    UnlockView()
        .environment(LockViewModel())
        .environment(\.dynamicTypeSize, .accessibility3)
}

/// Home payment actions use the existing shared checkout and unlock flow.
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

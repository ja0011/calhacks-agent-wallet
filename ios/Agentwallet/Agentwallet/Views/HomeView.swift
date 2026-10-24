//
//  HomeView.swift
//  Agentwallet
//

import FamilyControls
import ManagedSettings
import SwiftUI

/// First tab: lock status, balances, and recent activity at a glance.
struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Environment(ChatViewModel.self) private var wallet
    @Environment(LockViewModel.self) private var lock

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if wallet.isRefreshingWallet {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Updating…")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    LockCard(selectedTab: $selectedTab)
                    MoneyCard()
                    ActivityCard()

                    if let error = wallet.walletError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    WalletLimitsText()
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await wallet.refreshWallet() }
            .task { await wallet.refreshWallet() }
        }
    }
}

// MARK: - Lock card

private struct LockCard: View {
    @Binding var selectedTab: AppTab
    @Environment(LockViewModel.self) private var lock

    private static let valueFont = Font.system(size: 44, weight: .bold, design: .rounded)

    var body: some View {
        Card {
            // Not set up also covers the simulator, where Screen Time isn't authorized.
            if !lock.isAuthorized || !lock.hasSelection {
                notSetUp
            } else {
                switch lock.state {
                case .locked:
                    locked
                case .temporarilyUnlocked(let until):
                    unlocked(until: until)
                case .unlocked:
                    unlocked(until: nil)
                }
            }

            if let error = lock.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var notSetUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen Time lock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("No apps locked yet")
                .font(.title2.bold())
            Text("Pick the apps you can't put down.")
                .foregroundStyle(.secondary)
            Button {
                selectedTab = .unlock
            } label: {
                Text("Choose apps to lock").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(status: "Locked", icon: "lock.fill", color: .red)

            // Without a recorded lock time there's nothing to count from, so skip the value.
            if let lockedAt = lock.lockedAt {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.elapsedText(from: lockedAt, to: context.date))
                            .font(Self.valueFont)
                            .monospacedDigit()
                        Text("locked since \(lockedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            AppChips(selection: lock.selection)

            UnlockPaymentButtons()
        }
    }

    /// `until` is nil when apps are unlocked with no re-lock scheduled (not locked yet).
    private func unlocked(until: Date?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(status: "Unlocked", icon: "lock.open.fill", color: .green)

            if let until {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, until.timeIntervalSince(context.date))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
                            .font(Self.valueFont)
                            .monospacedDigit()
                        Text("until your apps lock again")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ProgressView(value: remaining, total: Config.unlockDuration)
                            .tint(.green)
                    }
                }
            } else {
                Text("Your apps aren't locked.")
                    .foregroundStyle(.secondary)
            }

            AppChips(selection: lock.selection)

            Button {
                lock.lockNow()
            } label: {
                Text("Lock now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func header(status: String, icon: String, color: Color) -> some View {
        HStack {
            Text("Screen Time lock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Label(status, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    /// "Xh Ym", or "Ym" under an hour.
    private static func elapsedText(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start)) / 60)
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// Up to 2 chips with the real icon and name of each selected item, then "+N".
private struct AppChips: View {
    let selection: FamilyActivitySelection

    private enum Chip: Hashable {
        case app(ApplicationToken)
        case category(ActivityCategoryToken)
        case webDomain(WebDomainToken)
    }

    /// Apps first, then categories and websites. Tokens are opaque, so sort by hash
    /// only to keep the order stable between redraws.
    private var chips: [Chip] {
        selection.applicationTokens.sorted { $0.hashValue < $1.hashValue }.map(Chip.app)
            + selection.categoryTokens.sorted { $0.hashValue < $1.hashValue }.map(Chip.category)
            + selection.webDomainTokens.sorted { $0.hashValue < $1.hashValue }.map(Chip.webDomain)
    }

    var body: some View {
        let chips = chips
        HStack(spacing: 8) {
            ForEach(chips.prefix(2), id: \.self) { chip in
                label(for: chip)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: .capsule)
            }
            if chips.count > 2 {
                Text("+\(chips.count - 2)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: .capsule)
            }
        }
    }

    @ViewBuilder
    private func label(for chip: Chip) -> some View {
        switch chip {
        case .app(let token): Label(token)
        case .category(let token): Label(token)
        case .webDomain(let token): Label(token)
        }
    }
}

// MARK: - Money card

private struct MoneyCard: View {
    @Environment(ChatViewModel.self) private var wallet

    var body: some View {
        Card {
            MoneyRow(icon: "building.columns.fill", title: "Bank", subtitle: "Checking, simulated",
                     amount: wallet.bankBalance ?? "-")
            Divider()
            MoneyRow(icon: "wallet.bifold.fill", title: "USDC wallet", subtitle: "Base Sepolia testnet",
                     amount: wallet.balance)
        }
    }
}

struct MoneyRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let amount: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: amount)
        }
    }
}

// MARK: - Activity card

private struct ActivityCard: View {
    @Environment(ChatViewModel.self) private var wallet

    var body: some View {
        Card {
            Text("Recent activity")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let items = wallet.recentActivity
            if items.isEmpty {
                Text("No activity yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    ActivityRow(item: item)
                }
            }
        }
    }
}

// MARK: - Card container

/// Rounded 12pt card used by every section on Home.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environment(ChatViewModel())
        .environment(LockViewModel())
        .preferredColorScheme(.dark)
}

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                Text(item.method)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.signedAmount)
                .monospacedDigit()
                .foregroundStyle(item.isIncoming ? Color.green : Color.primary)
        }
    }
}

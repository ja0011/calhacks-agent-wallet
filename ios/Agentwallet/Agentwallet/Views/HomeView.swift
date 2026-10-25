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
                VStack(spacing: 20) {
                    if wallet.isRefreshingWallet {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Updating…")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    LockCard(selectedTab: $selectedTab)
                    if let vault = wallet.vault, !vault.entries.isEmpty {
                        TimeVaultCard(vault: vault)
                    }
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
            .refreshable { await wallet.refreshWallet() }
            .task { await wallet.refreshWallet() }
        }
    }
}

// MARK: - Lock card

private struct LockCard: View {
    @Binding var selectedTab: AppTab
    @Environment(LockViewModel.self) private var lock

    private static let valueFont = Font.system(.largeTitle, design: .rounded, weight: .bold)

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
            HStack(spacing: 12) {
                HomeIconTile(symbol: "lock.fill")
                Text("App lock").font(.headline)
            }
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
                .controlSize(.large)
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                HomeIconTile(symbol: icon)
                Text("App lock").font(.headline)
                Spacer()
                Text(status).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 12) {
                HomeIconTile(symbol: icon)
                Text("App lock").font(.headline)
                Text(status).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            }
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
        ViewThatFits(in: .horizontal) {
            chipList(chips, vertical: false)
            chipList(chips, vertical: true)
        }
    }

    private func chipList(_ chips: [Chip], vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(chips.prefix(2), id: \.self) { chip in
                label(for: chip)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
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
            HomeMoneyRow(icon: "building.columns.fill", title: "Bank", subtitle: "Checking, simulated",
                     amount: wallet.bankBalance ?? "-")
            Divider()
            HomeMoneyRow(icon: "wallet.bifold.fill", title: "USDC wallet", subtitle: "Base Sepolia testnet",
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
                .font(.headline)

            let items = wallet.recentActivity
            if items.isEmpty {
                Text("No activity yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    HomeActivityRow(item: item)
                }
            }
        }
    }
}

// MARK: - Card container

/// Home cards grow with their content and Dynamic Type.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: 24))
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environment(ChatViewModel())
        .environment(LockViewModel())
        .preferredColorScheme(.light)
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

enum SpendyHomeStyle {
    static let background = Color(red: 247 / 255, green: 241 / 255, blue: 232 / 255)
    static let ink = Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)
    static let purple = Color(red: 111 / 255, green: 95 / 255, blue: 247 / 255)
    static let orange = Color(red: 255 / 255, green: 95 / 255, blue: 45 / 255)
}

struct SpendyHomeAvatar: View {
    @ScaledMetric(relativeTo: .title3) private var size = 40

    var body: some View {
        Image(systemName: "person.fill")
            .font(.title3)
            .foregroundStyle(SpendyHomeStyle.purple)
            .frame(width: size, height: size)
            .background(.white, in: .circle)
            .accessibilityLabel("Profile placeholder")
    }
}

struct HomeIconTile: View {
    let symbol: String
    @ScaledMetric(relativeTo: .title3) private var size = 48

    var body: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(SpendyHomeStyle.purple, in: .rect(cornerRadius: 15))
            .accessibilityHidden(true)
    }
}

struct HomeMoneyRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let amount: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HomeIconTile(symbol: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(amount)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: amount)
        }
    }
}

struct HomeActivityRow: View {
    let item: ActivityItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HomeIconTile(symbol: item.isIncoming ? "arrow.down.left" : "arrow.up.right")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label).font(.subheadline.weight(.semibold))
                Text(item.method).font(.caption).foregroundStyle(.secondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(item.signedAmount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.isIncoming ? Color.green : SpendyHomeStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Home — larger text") {
    HomeView(selectedTab: .constant(.home))
        .environment(ChatViewModel())
        .environment(LockViewModel())
        .environment(\.dynamicTypeSize, .accessibility3)
}

struct SpendyHeader: View {
    private let avatarSize: CGFloat = 32

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                brand
                Spacer(minLength: 12)
                SpendyHomeAvatar()
            }
            VStack(alignment: .leading, spacing: 12) {
                brand
                SpendyHomeAvatar()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(SpendyHomeStyle.background)
        .environment(\.colorScheme, .light)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: avatarSize, height: avatarSize)
                .background(SpendyHomeStyle.purple, in: .circle)
                .accessibilityHidden(true)
            Text("Spendy")
                .font(.title2.weight(.heavy))
                .foregroundStyle(SpendyHomeStyle.ink)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
        }
        .fixedSize()
    }
}

private struct TimeVaultCard: View {
    let vault: TimeVault

    var body: some View {
        Card {
            HStack(spacing: 12) {
                HomeIconTile(symbol: "lock.square.fill")
                Text("Time vault").font(.headline)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Locked away")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(vault.lockedTotal ?? "—")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.25), value: vault.lockedTotal)
                Text("\(vault.entries.count) unlocks so far")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(vault.entries.prefix(5)) { entry in
                TimeVaultEntryRow(entry: entry)
            }
            if vault.entries.count > 5 {
                Text("+\(vault.entries.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("In the full product, each unlock payment is held by a smart contract for 2 weeks. Here it's simulated.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TimeVaultEntryRow: View {
    let entry: TimeVault.Entry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.amount)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("locked \(TimeVault.Entry.displayDate(entry.lockedAt)) · returns \(TimeVault.Entry.displayDate(entry.releasesAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text("\(entry.daysLeft) days left")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SpendyHomeStyle.purple)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

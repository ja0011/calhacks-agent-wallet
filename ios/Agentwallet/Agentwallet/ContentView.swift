//
//  ContentView.swift
//  Agentwallet
//
//  Created by Jorge Acosta on 10/23/26.
//

import SwiftUI

/// Tabs in the root TabView. Shared so Home can switch tabs.
enum AppTab: Hashable {
    case home, chat, wallet, unlock
}

struct ContentView: View {
    @Environment(LockViewModel.self) private var lock
    @Environment(ChatViewModel.self) private var wallet
    @State private var selectedTab: AppTab = .home

    var body: some View {
        @Bindable var checkout = lock.checkout
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.chat)
            WalletView()
                .tabItem { Label("Wallet", systemImage: "wallet.bifold") }
                .tag(AppTab.wallet)
            UnlockView()
                .tabItem { Label("Unlock", systemImage: "lock.open") }
                .tag(AppTab.unlock)
        }
        .sheet(item: $checkout.session, onDismiss: {
            Task { await lock.cardCheckoutClosed(wallet: wallet) }
        }) { session in
            OnrampCheckoutView(title: "Unlock apps", session: session) { phase, paymentStatus in
                lock.checkout.checkoutUpdated(phase: phase, paymentStatus: paymentStatus)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(ChatViewModel())
        .environment(LockViewModel())
}

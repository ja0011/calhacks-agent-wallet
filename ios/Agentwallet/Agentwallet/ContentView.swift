//
//  ContentView.swift
//  Agentwallet
//
//  Created by Jorge Acosta on 10/23/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
            WalletView()
                .tabItem { Label("Wallet", systemImage: "wallet.bifold") }
            UnlockView()
                .tabItem { Label("Unlock", systemImage: "lock.open") }
        }
    }
}

#Preview {
    ContentView()
        .environment(ChatViewModel())
        .environment(LockViewModel())
}

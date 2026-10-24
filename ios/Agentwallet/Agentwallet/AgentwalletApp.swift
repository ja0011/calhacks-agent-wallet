//
//  AgentwalletApp.swift
//  Agentwallet
//
//  Created by Jorge Acosta on 10/23/26.
//

import SwiftUI

@main
struct AgentwalletApp: App {
    /// One view model shared by both tabs so balance and purchases stay in sync.
    @State private var chatViewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(chatViewModel)
        }
    }
}

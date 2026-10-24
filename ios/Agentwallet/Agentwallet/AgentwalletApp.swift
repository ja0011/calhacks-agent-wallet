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
    /// Screen Time lock state for the Unlock tab.
    @State private var lockViewModel = LockViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(chatViewModel)
                .environment(lockViewModel)
                .task {
                    // Ask for Family Controls authorization on launch; no prompt once approved.
                    if !lockViewModel.isAuthorized {
                        await lockViewModel.requestAuthorization()
                    }
                }
        }
        .onChange(of: scenePhase) {
            // Catch up on an unlock window that expired while the app was suspended.
            if scenePhase == .active {
                lockViewModel.refresh()
            }
        }
    }
}

//
//  Config.swift
//  Agentwallet
//

import Foundation

/// App-wide configuration. The app only talks to our own server — no API keys or secrets live here.
enum Config {
    /// Base URL of the local agent server. On the iOS Simulator, `localhost` resolves to the Mac.
    static let serverURL = "http://localhost:3000"
}

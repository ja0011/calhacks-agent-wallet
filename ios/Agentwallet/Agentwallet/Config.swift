//
//  Config.swift
//  Agentwallet
//

import Foundation

/// App-wide configuration. The app only talks to our own server — no API keys or secrets live here.
enum Config {
    /// Base URL of the local agent server. On the iOS Simulator, `localhost` resolves to the Mac.
    /// On a real iPhone, change this to the Mac's LAN address, e.g. "http://192.168.1.20:3000".
    static let serverURL = "http://localhost:3000"

    /// Unlock endpoint, called by the Unlock tab.
    static let unlockURL = URL(string: serverURL)?.appending(path: "api/unlock")

    /// How long apps stay unshielded after a successful unlock.
    static let unlockDuration: TimeInterval = 15 * 60
}

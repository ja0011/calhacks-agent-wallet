//
//  LockShared.swift
//  Agentwallet
//
//  Shared by the app and the DeviceActivityMonitor extension.
//  Add this file to the extension target's membership.
//

import DeviceActivity
import Foundation

nonisolated enum LockShared {
    /// App Group that lets the extension read the saved app selection.
    /// Must match the App Groups capability on both targets.
    static let appGroupID = "group.FB.Agentwallet"

    /// DeviceActivity window that runs while apps are temporarily unlocked.
    /// When it ends, the extension re-applies the shield.
    static let unlockWindowActivity = DeviceActivityName("agentwallet.unlockWindow")

    /// Shared defaults. Falls back to standard defaults if the App Group isn't configured yet.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

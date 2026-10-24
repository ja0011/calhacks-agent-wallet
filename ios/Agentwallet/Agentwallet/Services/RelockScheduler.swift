//
//  RelockScheduler.swift
//  Agentwallet
//

import DeviceActivity
import Foundation
import os

/// Schedules the unlock window with DeviceActivity so the system can wake the
/// DeviceActivityMonitor extension to re-lock, even if the app isn't running.
struct RelockScheduler {
    private let center = DeviceActivityCenter()
    private let logger = Logger(subsystem: "FB.Agentwallet", category: "Lock")

    /// Starts a one-off window from now until `end`. Must be at least 15 minutes long.
    /// Returns false if the system refused; the in-app timer still re-locks while the app is open.
    @discardableResult
    func startUnlockWindow(until end: Date) -> Bool {
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents(components, from: .now),
            intervalEnd: Calendar.current.dateComponents(components, from: end),
            repeats: false
        )
        do {
            try center.startMonitoring(LockShared.unlockWindowActivity, during: schedule)
            return true
        } catch {
            logger.error("DeviceActivity monitoring failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Ends the window early. The system calls the extension's `intervalDidEnd`, which re-locks.
    func stopUnlockWindow() {
        center.stopMonitoring([LockShared.unlockWindowActivity])
    }
}

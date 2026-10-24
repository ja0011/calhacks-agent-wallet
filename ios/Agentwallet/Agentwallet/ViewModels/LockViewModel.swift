//
//  LockViewModel.swift
//  Agentwallet
//

import FamilyControls
import Foundation
import Observation

/// Drives the Unlock tab: Family Controls authorization, the app selection,
/// and the locked / temporarily-unlocked state.
@Observable
final class LockViewModel {
    enum LockState: Equatable {
        /// No lock applied.
        case unlocked
        /// Shield is on.
        case locked
        /// Server approved an unlock; shield comes back at `until`.
        case temporarilyUnlocked(until: Date)
    }

    var authorizationStatus: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    var selection: FamilyActivitySelection
    private(set) var state: LockState = .unlocked
    private(set) var isUnlocking = false
    var errorMessage: String?

    private let shield = ShieldService()
    private let scheduler = RelockScheduler()
    private let client: APIClient
    private let defaults = UserDefaults.standard
    private let lockedKey = "lock.isLocked"
    private let unlockUntilKey = "lock.unlockUntil"

    @ObservationIgnored private var relockTask: Task<Void, Never>?

    init(client: APIClient = APIClient()) {
        self.client = client
        self.selection = shield.loadSelection()
        restoreState()
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    // MARK: - Authorization

    /// Requests individual Family Controls authorization. Apple recommends calling this on launch;
    /// once approved, later calls return immediately without prompting.
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            errorMessage = nil
        } catch {
            errorMessage = "Screen Time authorization failed: \(error.localizedDescription)"
        }
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    // MARK: - Selection

    func selectionChanged() {
        shield.saveSelection(selection)
        // Keep an active lock in sync with the new selection.
        if state == .locked {
            shield.applyShield(for: selection)
        }
    }

    // MARK: - Lock / unlock

    func lockNow() {
        guard hasSelection else {
            errorMessage = "Choose at least one app to lock."
            return
        }
        relockTask?.cancel()
        relockTask = nil
        scheduler.stopUnlockWindow()
        shield.applyShield(for: selection)
        errorMessage = nil
        setState(.locked)
    }

    /// Asks the server for permission. Only HTTP 200 lifts the shield; anything else keeps it on.
    func unlock() async {
        guard state == .locked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }

        do {
            try await client.requestUnlock()
            shield.clearShield()
            errorMessage = nil
            let until = Date.now.addingTimeInterval(Config.unlockDuration)
            setState(.temporarilyUnlocked(until: until))
            // Background re-lock via the DeviceActivityMonitor extension...
            scheduler.startUnlockWindow(until: until)
            // ...plus an in-app timer so the screen flips to Locked on time while open.
            scheduleRelock(at: until)
        } catch {
            errorMessage = "Unlock denied: \(error.localizedDescription)"
        }
    }

    /// Re-applies the lock if the unlock window has passed. Called when the app becomes active,
    /// because the in-app timer doesn't run while the app is suspended. (The extension may
    /// already have re-applied the shield; applying it again is harmless.)
    func refresh() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        if case .temporarilyUnlocked(let until) = state {
            if until <= .now {
                relock()
            } else if relockTask == nil {
                scheduleRelock(at: until)
            }
        }
    }

    // MARK: - Private

    private func scheduleRelock(at date: Date) {
        relockTask?.cancel()
        relockTask = Task { [weak self] in
            let delay = date.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.relock()
        }
    }

    private func relock() {
        relockTask = nil
        scheduler.stopUnlockWindow()
        shield.applyShield(for: selection)
        setState(.locked)
    }

    private func setState(_ newState: LockState) {
        state = newState
        switch newState {
        case .unlocked:
            defaults.set(false, forKey: lockedKey)
            defaults.removeObject(forKey: unlockUntilKey)
        case .locked:
            defaults.set(true, forKey: lockedKey)
            defaults.removeObject(forKey: unlockUntilKey)
        case .temporarilyUnlocked(let until):
            defaults.set(true, forKey: lockedKey)
            defaults.set(until, forKey: unlockUntilKey)
        }
    }

    private func restoreState() {
        guard defaults.bool(forKey: lockedKey) else {
            state = .unlocked
            return
        }
        if let until = defaults.object(forKey: unlockUntilKey) as? Date, until > .now {
            state = .temporarilyUnlocked(until: until)
            scheduleRelock(at: until)
        } else {
            // Either locked, or the unlock window expired while the app wasn't running.
            relock()
        }
    }
}

//
//  ShieldService.swift
//  Agentwallet
//
//  Shared by the app and the DeviceActivityMonitor extension.
//  Add this file to the extension target's membership.
//

import FamilyControls
import Foundation
import ManagedSettings

/// Applies and clears Screen Time shields, and persists the app selection.
/// Shields set on a `ManagedSettingsStore` persist after the app is suspended or quit,
/// and the app and its extensions share the same default store.
nonisolated struct ShieldService {
    private let store = ManagedSettingsStore()
    private let selectionKey = "lock.selection"

    /// Covers the selected apps, categories, and websites with a shield.
    func applyShield(for selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        // Record when the lock started. Re-applying an existing shield (app relaunch,
        // selection change) keeps the original time, so elapsed time doesn't reset.
        if LockShared.lockedAt == nil {
            LockShared.defaults.set(Date.now, forKey: LockShared.lockedAtKey)
        }
    }

    /// Removes every shield this app applied.
    func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        LockShared.defaults.removeObject(forKey: LockShared.lockedAtKey)
    }

    func loadSelection() -> FamilyActivitySelection {
        // Older builds saved to standard defaults; read that if the App Group copy is missing.
        let data = LockShared.defaults.data(forKey: selectionKey)
            ?? UserDefaults.standard.data(forKey: selectionKey)
        guard let data,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return FamilyActivitySelection()
        }
        return selection
    }

    func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            LockShared.defaults.set(data, forKey: selectionKey)
        }
    }
}

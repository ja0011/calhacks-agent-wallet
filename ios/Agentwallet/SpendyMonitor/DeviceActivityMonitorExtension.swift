import DeviceActivity

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == LockShared.unlockWindowActivity else { return }
        let shield = ShieldService()
        shield.applyShield(for: shield.loadSelection())
    }
}

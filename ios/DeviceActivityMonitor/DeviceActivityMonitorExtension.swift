import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

/// Applies and lifts the app shield at schedule boundaries.
///
/// This runs in a SEPARATE process from the main app — a DeviceActivity
/// monitor extension the system wakes when a scheduled interval begins or ends.
/// It shares nothing with the app except the App Group container, so the
/// selected-app tokens are read from there rather than passed in.
///
/// TARGET SETUP (Xcode): this file belongs to a new "Device Activity Monitor
/// Extension" target, not the Runner app target. See ios/README-iOS.md.
@available(iOS 16.0, *)
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .prayerLock)
    private let sharedDefaults = UserDefaults(suiteName: "group.com.prayerlock.shared")

    /// Interval began — a prayer window opened. Shield the selected apps.
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard let selection = loadSelection() else { return }

        // A nil (not empty) set means "shield nothing"; an empty non-nil set
        // would shield everything, locking the user out of their whole phone.
        store.shield.applications =
            selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty
                ? nil
                : .specific(selection.categoryTokens)

        sharedDefaults?.set(true, forKey: "prayerlock.isLocked")
    }

    /// Interval ended — the prayer window closed. Lift the shield.
    ///
    /// The app also lifts it early when the user verifies; this is the backstop
    /// for the case where they never do, so the shield is not left on all day.
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        store.shield.applications = nil
        store.shield.applicationCategories = nil
        sharedDefaults?.set(false, forKey: "prayerlock.isLocked")
    }

    private func loadSelection() -> FamilyActivitySelection? {
        guard
            let data = sharedDefaults?.data(forKey: "prayerlock.selection"),
            let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return nil
        }
        return selection
    }
}

@available(iOS 16.0, *)
private extension ManagedSettingsStore.Name {
    static let prayerLock = Self("prayerLock")
}

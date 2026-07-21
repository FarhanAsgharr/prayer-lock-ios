import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

/// iOS app-restriction using Apple's Screen Time (Family Controls) API.
///
/// This is architecturally different from the Android implementation and the
/// difference is imposed by Apple, not chosen:
///
/// - We cannot see which app is in the foreground, and cannot draw a custom
///   lock screen over another app. Apple forbids both for privacy.
/// - Instead, the user picks apps through Apple's own `FamilyActivityPicker`,
///   which returns opaque tokens — we never learn which apps they are.
/// - We "shield" those tokens with a `ManagedSettingsStore`. When the user
///   opens a shielded app, iOS itself shows a shield screen; our
///   `ShieldConfiguration` extension customises its text and button.
/// - Scheduling is done with `DeviceActivity`, whose monitor extension is
///   woken by the system at interval boundaries to apply or lift the shield.
///
/// The net product behaviour matches Android — selected apps are unavailable
/// during prayer and released after verification — but the mechanism, and the
/// lock UI, are Apple's rather than ours.
///
/// NOTE: This file requires the Family Controls entitlement to do anything at
/// runtime. It compiles without it, and every method degrades safely when
/// authorization has not been granted.
@available(iOS 16.0, *)
final class BlockingManager {

    static let shared = BlockingManager()

    /// The shield store. A named store rather than the default so its settings
    /// are isolated and can be cleared wholesale on release.
    private let store = ManagedSettingsStore(named: .prayerLock)

    /// Shared container for passing the selection and lock state to the
    /// extensions, which run in separate processes.
    private let sharedDefaults = UserDefaults(suiteName: "group.com.prayerlock.shared")

    private init() {}

    // MARK: - Authorization

    /// Whether Family Controls authorization has been granted.
    var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Request authorization. Presents Apple's system prompt.
    ///
    /// `.individual` rather than `.child`: this app restricts the owner's own
    /// device by their own choice, which is a fundamentally different use from
    /// a parent restricting a child, and Apple treats the two distinctly.
    func requestAuthorization() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return isAuthorized
        } catch {
            NSLog("Family Controls authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - App selection

    /// Persist the user's app selection.
    ///
    /// The selection is a set of opaque tokens produced by Apple's picker,
    /// which the Flutter layer presents. We store it so the monitor extension
    /// can apply the same set when a schedule boundary fires.
    func saveSelection(_ selection: FamilyActivitySelection) {
        guard let encoded = try? JSONEncoder().encode(selection) else { return }
        sharedDefaults?.set(encoded, forKey: .selectionKey)
    }

    func loadSelection() -> FamilyActivitySelection {
        guard
            let data = sharedDefaults?.data(forKey: .selectionKey),
            let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            return FamilyActivitySelection()
        }
        return selection
    }

    // MARK: - Locking

    /// Shield the selected apps now.
    ///
    /// Idempotent: applying an identical shield twice is a no-op, matching the
    /// orchestrator's converge-on-desired-state model on the Android side.
    func startLock(prayerName: String) {
        guard isAuthorized else { return }

        let selection = loadSelection()

        // Shield the chosen applications and categories. Passing an empty set
        // as nil is important — an empty (non-nil) set shields *everything*,
        // which would lock the user out of their whole phone.
        store.shield.applications =
            selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty
                ? nil
                : .specific(selection.categoryTokens)

        sharedDefaults?.set(true, forKey: .isLockedKey)
        sharedDefaults?.set(prayerName, forKey: .prayerNameKey)
    }

    /// Lift the shield.
    func stopLock() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        sharedDefaults?.set(false, forKey: .isLockedKey)
    }

    var isLocked: Bool {
        sharedDefaults?.bool(forKey: .isLockedKey) ?? false
    }

    // MARK: - Scheduling

    /// One prayer's blocking window, in local wall-clock components.
    struct Window {
        let name: String
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
    }

    /// Schedule the shield to apply during each prayer's window every day.
    ///
    /// This is what makes iOS blocking work when the app is closed. The app
    /// cannot run a background timer the way Android can, so instead it hands
    /// the system a repeating daily schedule per prayer; the
    /// DeviceActivityMonitor extension is woken at each window's start to apply
    /// the shield and at its end to lift it. The app additionally lifts the
    /// shield early, in the foreground, the moment the user verifies.
    ///
    /// A separate `DeviceActivityName` per prayer keeps the five windows
    /// independent, so completing one prayer's window never disturbs another.
    func scheduleWindows(_ windows: [Window]) {
        guard isAuthorized else { return }

        let center = DeviceActivityCenter()

        // Clear the whole previous set first. Windows shift daily with the sun,
        // so stale schedules from an earlier day must not linger.
        center.stopMonitoring(center.activities)

        for window in windows {
            // Skip a zero-length or inverted window rather than let the system
            // reject the whole batch.
            guard !(window.startHour == window.endHour
                && window.startMinute == window.endMinute) else { continue }

            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(
                    hour: window.startHour, minute: window.startMinute
                ),
                intervalEnd: DateComponents(
                    hour: window.endHour, minute: window.endMinute
                ),
                repeats: true
            )

            do {
                try center.startMonitoring(
                    DeviceActivityName("prayerLock.\(window.name)"),
                    during: schedule
                )
            } catch {
                NSLog(
                    "DeviceActivity scheduling failed for \(window.name): "
                        + error.localizedDescription
                )
            }
        }
    }

    func cancelSchedule() {
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities)
    }
}

// MARK: - Shared keys

private extension String {
    static let selectionKey = "prayerlock.selection"
    static let isLockedKey = "prayerlock.isLocked"
    static let prayerNameKey = "prayerlock.prayerName"
}

@available(iOS 16.0, *)
private extension ManagedSettingsStore.Name {
    static let prayerLock = Self("prayerLock")
}

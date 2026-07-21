import Flutter
import UIKit
import SwiftUI
import FamilyControls

/// Bridges the Dart `com.prayerlock/blocking` MethodChannel to the iOS
/// Screen Time implementation.
///
/// The method names mirror the Android channel so the shared Dart
/// `BlockingPlatformChannel` needs no platform branching. Where a concept has
/// no iOS equivalent — enumerating installed apps, for instance, which Apple
/// forbids — the method returns an honest empty or unsupported result rather
/// than a fabricated one.
@available(iOS 16.0, *)
final class BlockingChannel {

    private let manager = BlockingManager.shared
    private weak var controller: FlutterViewController?

    init(controller: FlutterViewController) {
        self.controller = controller
    }

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.prayerlock/blocking",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPermissionStatus":
            // iOS has one gate — Family Controls authorization — where Android
            // has three. Map it onto the same shape the Dart layer expects, so
            // the permissions UI is shared.
            let authorized = manager.isAuthorized
            result([
                "usageStats": authorized,
                "overlay": authorized,
                "batteryOptimizationDisabled": true,
            ])

        case "requestUsageStatsPermission", "requestOverlayPermission":
            // Both map to the single Family Controls prompt. Requesting twice
            // is harmless — the system prompt only appears once.
            Task {
                _ = await self.manager.requestAuthorization()
                result(nil)
            }

        case "requestDisableBatteryOptimization":
            // No iOS equivalent; nothing to do.
            result(nil)

        case "getInstalledApps":
            // Apple deliberately does not expose the installed-app list. The
            // user picks apps through the system picker instead, so this
            // returns empty rather than a fake list.
            result([])

        case "presentAppPicker":
            self.presentPicker(result: result)

        case "startLock":
            let args = call.arguments as? [String: Any]
            let prayerName = args?["prayerName"] as? String ?? "prayer"
            guard manager.isAuthorized else {
                result(FlutterError(
                    code: "MISSING_AUTHORIZATION",
                    message: "Screen Time access has not been granted.",
                    details: nil
                ))
                return
            }
            manager.startLock(prayerName: prayerName)
            result(true)

        case "stopLock":
            manager.stopLock()
            result(true)

        case "updateBlockedApps":
            // The selection is updated through the picker on iOS, so a token
            // list from Dart is not applicable; acknowledge without change.
            result(true)

        case "scheduleWindows":
            // The Dart side computes each prayer's blocking window and hands
            // them here to be scheduled with DeviceActivity, so blocking works
            // even when the app is closed.
            let args = call.arguments as? [String: Any]
            let raw = args?["windows"] as? [[String: Any]] ?? []
            let windows = raw.compactMap { entry -> BlockingManager.Window? in
                guard
                    let name = entry["name"] as? String,
                    let sh = entry["startHour"] as? Int,
                    let sm = entry["startMinute"] as? Int,
                    let eh = entry["endHour"] as? Int,
                    let em = entry["endMinute"] as? Int
                else { return nil }
                return BlockingManager.Window(
                    name: name,
                    startHour: sh, startMinute: sm,
                    endHour: eh, endMinute: em
                )
            }
            manager.scheduleWindows(windows)
            result(true)

        case "cancelSchedule":
            manager.cancelSchedule()
            result(true)

        case "hasAdhanSound":
            result(Bundle.main.url(forResource: "adhan", withExtension: "caf") != nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Present Apple's `FamilyActivityPicker` and persist the chosen selection.
    ///
    /// The picker is the only way to select apps on iOS; the app never sees
    /// which apps were chosen, only opaque tokens.
    private func presentPicker(result: @escaping FlutterResult) {
        guard manager.isAuthorized else {
            result(FlutterError(
                code: "MISSING_AUTHORIZATION",
                message: "Screen Time access has not been granted.",
                details: nil
            ))
            return
        }

        let picker = AppPickerHostingController { selection in
            self.manager.saveSelection(selection)
            result(selection.applicationTokens.count + selection.categoryTokens.count)
        }
        controller?.present(picker, animated: true)
    }
}

/// Hosts the SwiftUI `FamilyActivityPicker` inside a UIKit modal so it can be
/// presented from the Flutter view controller.
@available(iOS 16.0, *)
final class AppPickerHostingController: UIViewController {

    private let onDone: (FamilyActivitySelection) -> Void
    private var selection = FamilyActivitySelection()

    init(onDone: @escaping (FamilyActivitySelection) -> Void) {
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let picker = FamilyActivityPickerView(
            selection: Binding(
                get: { self.selection },
                set: { self.selection = $0 }
            ),
            onDone: { [weak self] in
                guard let self else { return }
                self.onDone(self.selection)
                self.dismiss(animated: true)
            }
        )

        let host = UIHostingController(rootView: picker)
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)
    }
}

/// SwiftUI wrapper adding a Done button to Apple's picker, which ships without
/// one of its own.
@available(iOS 16.0, *)
struct FamilyActivityPickerView: View {
    @Binding var selection: FamilyActivitySelection
    let onDone: () -> Void

    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle("Choose apps to pause")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
    }
}

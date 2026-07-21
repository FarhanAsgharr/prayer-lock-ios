import ManagedSettings
import Foundation

/// Handles taps on the buttons of the shield screen.
///
/// The shield's buttons are defined in `ShieldConfigurationExtension`; this
/// separate extension is what iOS calls when one is pressed. Apple does not
/// permit an extension to launch the main app directly, so the primary button
/// dismisses the shield and the user opens Prayer Lock themselves to verify.
///
/// This is the closest iOS permits to the Android flow. It is intentionally
/// conservative: it never lifts the shield itself (only the app, after
/// verification, or the schedule's end does that), so the button cannot be
/// used to bypass the block.
///
/// TARGET SETUP (Xcode): belongs to a "Shield Action" extension target. The
/// project script wires this up; see ios/README-iOS.md.
@available(iOS 16.0, *)
final class ShieldActionExtension: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    /// Map a button press to a response.
    ///
    /// - `.primaryButtonPressed` ("Open Prayer Lock"): close the shield so the
    ///   user can go open the app and verify. The app itself stays shielded —
    ///   closing only dismisses this screen, it does not lift the block.
    /// - `.secondaryButtonPressed`: there is no secondary button, but iOS
    ///   requires the case to be handled; defer briefly and re-shield.
    private func response(for action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            return .close
        case .secondaryButtonPressed:
            return .defer
        @unknown default:
            return .none
        }
    }
}

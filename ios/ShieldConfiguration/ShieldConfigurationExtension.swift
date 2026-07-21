import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Customises the shield screen iOS shows when the user opens a blocked app.
///
/// This is the iOS counterpart to the Android lock screen, but constrained:
/// Apple renders it, in its own process, from this configuration. We cannot run
/// Flutter here or add arbitrary controls — only the title, subtitle, icon and
/// up to two buttons Apple exposes. The tone is kept identical to the Android
/// lock screen: calm, brief, and never trapping the user.
///
/// The "primary" button label reads "I have prayed"; tapping it defers the
/// shield for this app, which returns the user to it. The app then records the
/// prayer on next launch. Emergency access is inherent on iOS — the shield
/// never covers Phone, Messages or Settings, because Apple's own shield only
/// applies to the apps the user selected.
///
/// TARGET SETUP (Xcode): this belongs to a "Shield Configuration" extension
/// target. See ios/README-iOS.md.
@available(iOS 16.0, *)
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private let sharedDefaults = UserDefaults(suiteName: "group.com.prayerlock.shared")

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        buildConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        buildConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        buildConfiguration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        buildConfiguration()
    }

    private func buildConfiguration() -> ShieldConfiguration {
        let prayerName = sharedDefaults?.string(forKey: "prayerlock.prayerName") ?? "prayer"

        // An SF Symbol rather than a bundled asset: it needs no asset catalog,
        // is always present on iOS 13+, and renders crisply at any size. The
        // extension has its own bundle, so it could not share the app's icon
        // asset anyway.
        let icon = UIImage(systemName: "moon.stars.fill")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(red: 0.06, green: 0.08, blue: 0.07, alpha: 1.0),
            icon: icon,
            title: ShieldConfiguration.Label(
                text: "It's time for \(prayerName.capitalized)",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Please perform your prayer. Open Prayer Lock to confirm "
                    + "and unlock your apps.",
                color: UIColor(white: 0.7, alpha: 1.0)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open Prayer Lock",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(
                red: 0.11, green: 0.36, blue: 0.29, alpha: 1.0
            ),
            secondaryButtonLabel: nil
        )
    }
}

# iOS build, signing and deployment

Everything that can be done in code **is done**. The Swift, the three Screen
Time extensions, all entitlements, Info.plist entries, the Podfile, and the
Xcode project targets are configured and verified as far as is possible without
a Mac:

- All 6 Swift files pass `swiftc -parse` with zero syntax errors.
- All 8 plist/entitlement files pass `plutil -lint`.
- The `.xcodeproj` was configured programmatically and **reopens cleanly** with
  all 5 targets, correct build settings, entitlements, and the embed phase.

What remains is only what genuinely requires **your Mac, your Apple Developer
account, and Apple's approval** — listed explicitly at the end. No code changes
are needed for any of it.

> **Honest status:** this project has **not been compiled**, because compiling
> iOS needs Xcode with the full iOS SDK, which is not available in the
> environment it was built in. Treat "it builds" as expected-but-unproven until
> you run step 4 on a Mac. Everything up to the compiler has been verified.

---

## What works on iOS without Apple's Family Controls entitlement

The Flutter layer is cross-platform, so these work as soon as the project
builds — no entitlement required:

- Prayer-time calculation (identical engine to Android, parity-tested to 1s)
- Reminders and the adhan (local notifications, exact scheduling)
- Prayer tracking, streaks, statistics, the analytics screen and charts
- Camera-based prayer verification
- The encrypted local database (SQLCipher) and offline sync queue
- All four schools of jurisprudence, including the Ja'fari Maghrib rule

Only **app blocking** waits on the entitlement. Until it is granted, the app
builds, installs and runs; the blocking UI reports itself unavailable and every
other feature works — so you can ship to TestFlight while you wait.

---

## Prerequisites

- macOS with **Xcode 15+**
- **CocoaPods** — `sudo gem install cocoapods`
- The **xcodeproj** Ruby gem — `gem install xcodeproj` (used by the project
  configuration script; pure Ruby, no Xcode needed)
- A physical **iPhone on iOS 16+** (Screen Time APIs do nothing in the
  Simulator)
- A paid **Apple Developer account** ($99/year)

## 1. Fetch Flutter dependencies and pods

```bash
cd mobile
flutter pub get
cd ios
pod install
```

## 2. Re-apply the extension targets (only if the project was regenerated)

The three Screen Time extension targets are already in `Runner.xcodeproj`. But
`flutter clean`, or a fresh `flutter create` over the project, regenerates the
base project and drops them. If that happens, re-add them with one command — it
is idempotent and safe to run any time:

```bash
cd ios
ruby configure_project.rb
```

This adds the `DeviceActivityMonitor`, `ShieldConfiguration` and `ShieldAction`
targets, wires their entitlements and Info.plists, embeds them in the app, and
attaches the blocking sources and the app entitlement to Runner.

## 3. Open the workspace and set signing

```bash
open Runner.xcworkspace   # the workspace, never the .xcodeproj
```

In Xcode, for **each of the four targets** (Runner + the three extensions):

- **Signing & Capabilities → Team**: select your Apple Developer team.
- Signing is set to **Automatic**; Xcode will create the provisioning profiles.

The bundle identifiers are already set and correctly prefixed:

| Target | Bundle ID |
|---|---|
| Runner | `com.prayerlock.prayerLock` |
| DeviceActivityMonitor | `com.prayerlock.prayerLock.DeviceActivityMonitor` |
| ShieldConfiguration | `com.prayerlock.prayerLock.ShieldConfiguration` |
| ShieldAction | `com.prayerlock.prayerLock.ShieldAction` |

> If you use your own bundle-id prefix, change it in `configure_project.rb`
> (the `APP_BUNDLE_ID` constant) and in Runner's build settings, then re-run the
> script. Keep the extension suffixes.

## 4. Build and run on a device

```bash
flutter run --release -d <your-iphone>
# or from Xcode: select your iPhone and press Run
```

Fix nothing — but if the compiler flags anything, it will almost certainly be a
signing/team issue from step 3, not a code issue.

## 5. Create the App Group and request the entitlement

Two things must happen in the Apple Developer portal for blocking to function.
Both are account-level, not code:

### App Group (do this now)
Create an App Group **`group.com.prayerlock.shared`** and enable it (Signing &
Capabilities → App Groups) on **all four targets**. The app and the extensions
share the selected-app tokens and lock state only through this group.

### Family Controls entitlement (start now — it is the long pole)
Apply at
<https://developer.apple.com/contact/request/family-controls-distribution>.

The entitlement `com.apple.developer.family-controls` is already declared in
every target's `.entitlements` file, but it is inert until Apple attaches it to
your account. Approval takes **weeks** and can be refused. Nothing in the code
changes when it arrives — blocking simply begins working.

---

## How iOS blocking works, once the entitlement is granted

The mechanism is Apple's and differs from Android by design:

1. On first run the app requests **Screen Time authorization** (the Family
   Controls prompt).
2. In *Blocked apps*, the user taps **Choose apps** and selects them through
   **Apple's own picker**. The app never learns which apps — it only gets
   opaque tokens.
3. The app schedules a **DeviceActivity** window for each prayer (start + grace
   period → end of window), in local time.
4. When a window begins, the **DeviceActivityMonitor** extension shields the
   selected apps. Opening one shows the **ShieldConfiguration** screen ("It's
   time for &lt;prayer&gt;").
5. The user opens Prayer Lock, verifies, and the app lifts the shield early.
   Otherwise the window's end lifts it automatically.

Emergency access is inherent: only the apps the user picked are ever shielded,
so Phone, Messages and Settings are never blocked — no allowlist needed.

---

## TestFlight

1. In Xcode: **Product → Archive** (with a Release configuration and a real
   device selected as the destination).
2. In the Organizer, **Distribute App → App Store Connect → Upload**.
3. In [App Store Connect](https://appstoreconnect.apple.com): create the app
   record (bundle id `com.prayerlock.prayerLock`), then add the build to
   **TestFlight**.
4. Add testers by email or a public link. TestFlight builds may run **without**
   the Family Controls entitlement — blocking is simply inactive in that build.

## App Store submission

- **Screenshots**: 6.7" and 5.5" iPhone sizes are required.
- **Privacy nutrition labels**: declare camera use; declare that images are
  **not** stored and location **does not leave the device**.
- **Review notes**: state plainly that this is a **self-imposed,
  user-configured** restriction on the user's own device — not parental control
  and not surveillance — with a self-service way to disable it. Family Controls
  apps get extra scrutiny; the entitlement grant is the real gate, and App
  Review is generally smoother once you hold it.
- **Age rating, support URL, privacy policy URL**: required; the privacy policy
  must state that verification images are discarded and never uploaded.

---

## The complete list of remaining manual steps

Everything below needs **your** Mac or **your** Apple account — none needs code:

1. Open the workspace in Xcode and select your team on the four targets (step 3).
2. Create the App Group `group.com.prayerlock.shared` on all four targets.
3. Apply for, and receive, the Family Controls entitlement (weeks).
4. Archive and upload to TestFlight / the App Store.
5. Provide store metadata: screenshots, privacy labels, a privacy policy URL,
   and review notes.

Point the app at your hosted backend by building with:

```bash
flutter build ios --release --dart-define=API_BASE_URL=https://your-backend.example.com
```

Without it, the app is fully functional offline; only cloud sync is inactive.

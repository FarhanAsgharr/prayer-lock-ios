# Prayer Lock — iOS

Pray on time, with fewer distractions. Prayer Lock detects your prayer times,
pauses the apps you choose during each prayer using Apple's Screen Time, and
releases them once you confirm you have prayed.

This repository is the **iPhone** app. The Android version lives in a separate
repository.

---

## Important: iPhone cannot install a downloaded file

Unlike Android, Apple does not allow installing an app from a downloaded file.
An iPhone app must come from the **App Store**, **TestFlight**, or be **built in
Xcode onto your own device**. All three need a Mac with Xcode and a paid Apple
Developer account ($99/year).

There is therefore no APK-equivalent to download here. To run this on an iPhone
you (or a developer) must build it — see below.

## What works, and what waits on Apple

Everything except app blocking works as soon as the project builds:

- Accurate prayer times (all four schools, incl. the Ja'fari Maghrib rule)
- Reminders and the adhan
- Prayer tracking, streaks, statistics and charts
- Camera-based prayer verification
- Encrypted on-device storage and offline sync

**App blocking** uses Apple's Family Controls / Screen Time, which requires a
special entitlement Apple grants only on a written request (weeks, and it can be
refused). Until it is granted the app builds and runs and blocking simply
reports itself unavailable — so it can ship to TestFlight meanwhile.

---

## Build and run (developer, on a Mac)

Full step-by-step instructions, including signing, the App Group, the
entitlement request, TestFlight and App Store submission, are in
[`ios/README-iOS.md`](ios/README-iOS.md).

Short version:

```bash
flutter pub get
cd ios
pod install
ruby configure_project.rb   # re-adds the Screen Time extension targets if needed
open Runner.xcworkspace
```

Then in Xcode: select your team on all four targets, plug in an iPhone (iOS
16+), and press Run.

## The Screen Time extensions

App blocking is implemented with three system extensions, already written and
configured in this project:

| Extension | Role |
|---|---|
| DeviceActivityMonitor | Applies/lifts the app shield at each prayer window |
| ShieldConfiguration | The "It's time for prayer" screen shown over a blocked app |
| ShieldAction | Handles taps on the shield's button |

`ios/configure_project.rb` adds these targets to the Xcode project
programmatically, so they survive a `flutter clean`. Run it any time the base
project is regenerated.

## Tests

```bash
flutter test   # Dart unit and widget tests (same suite as Android)
```

## Backend (optional)

The app is fully functional offline. To enable cloud sync, build against a
hosted backend:

```bash
flutter build ios --release --dart-define=API_BASE_URL=https://your-backend.example.com
```

# iOS/TestFlight adaptation design

## Goal

Make the existing Flutter app available to iPhone users under the name **圣经背诵**, preserving Android behavior and distributing iOS beta builds through TestFlight.

## Scope and platform boundary

The Flutter domain, UI, SQLite data model, offline scripture assets, and quiz logic remain shared. Native code and platform-specific behavior are isolated behind platform checks or small service interfaces.

Android-only behavior remains unchanged:

- APK download, integrity verification, and in-app installation.
- MediaStore-based JSON and QR image saving.
- Android notification channel and exact-alarm handling.

iOS behavior:

- Use iOS file save UI for plan and quiz-bank JSON exports.
- Do not expose the Android APK QR flow on iOS. The existing QR is only an Android APK download link and has no iOS equivalent.
- Configure iOS local notifications with the current reminder schedule semantics where platform support permits.
- Add microphone privacy text and verify offline recording/recognition on an iPhone.
- Never offer an APK QR code. Once a TestFlight public link exists, show a clearly labeled TestFlight join action that opens the link. Until then, omit the action rather than present an unusable placeholder.

## iOS project configuration

- App display name: `圣经背诵`.
- Bundle identifier: `app.biblerecite`, subject to availability in the Apple Developer account.
- Minimum deployment target: iOS 13.0.
- Add the privacy usage description required for microphone access. No Photos permission is needed because iOS does not expose the Android APK QR flow.
- Configure release signing only after the Apple Developer Program membership is active; no Apple credentials are stored in the repository.

## Architecture

1. Extract export and share/save operations currently embedded in presentation widgets into platform-aware services. Each service has a testable interface and injectable implementation.
2. Keep Android `MethodChannel` implementations and registrations intact. Add Swift channel handlers only where iOS requires native Photos behavior; prefer existing cross-platform Flutter APIs for document export.
3. Extend the reminder scheduler with iOS initialization, permission request, and notification details while retaining Android-specific exact-alarm behavior behind an Android branch.
4. Replace hard-coded Android-only QR assumptions with an explicit distribution-link configuration. The iOS branch shows no distribution UI until the TestFlight URL is supplied.
5. Keep the update subsystem Android-only. iOS shows no download/install flow because TestFlight handles build delivery.

## Validation

- Add unit/widget tests for platform service selection, export cancellation, TestFlight-link visibility, and reminder configuration.
- Run formatter, static analysis, and the complete Flutter test suite.
- Build an Android release after the iOS changes and verify Android platform-channel behavior remains selected.
- Build and run an iOS Simulator build for shared UI/data flows.
- Before external TestFlight distribution, verify microphone, notification authorization/delivery, Photos save, document export/import, and offline recognition on an iPhone owned by a tester.

## TestFlight release sequence

1. Enroll in the Apple Developer Program as an individual; the App Store developer name will be the account holder's legal name.
2. Register the identifier and create the app record in App Store Connect.
3. Archive and upload a signed iOS build, supply TestFlight test notes and export-compliance answers, then test internally.
4. Submit the first external build for TestFlight review, then distribute the approved public link or email invitations.
5. Place the resulting public TestFlight URL in the distribution configuration and release a follow-up build if needed.

## Constraints

- The local workstation currently has Xcode 26.6 but no `flutter` executable on `PATH`; locate or install the project-compatible Flutter 3.44.4 toolchain before builds.
- No physical iPhone is currently available, so device-only validation is an external TestFlight acceptance gate, not something a simulator can replace.

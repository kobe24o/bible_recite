# iOS/TestFlight Adaptation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an iPhone-compatible build named 圣经背诵 while preserving Android APK behavior and preparing a future TestFlight distribution path.

**Architecture:** A testable runtime-platform provider separates the few platform-specific UI, update, and notification paths. Android native channels remain untouched. A typed TestFlight URL is supplied with `--dart-define` rather than committed to source.

**Tech Stack:** Flutter 3.44.4, Dart, Riverpod, `flutter_local_notifications`, `file_selector`, Xcode 26.6, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-04-ios-testflight-design.md`

## Global Constraints

- iOS display name is `圣经背诵`; minimum target is iOS 13.0; bundle ID remains `app.biblerecite`.
- Android APK updates, QR, MediaStore exports, and exact alarms are unchanged.
- iOS hides APK QR and shows a TestFlight action only for a valid `https://testflight.apple.com/...` URL.
- Every behavioral production change follows a verified failing test.

### Task 1: Platform and TestFlight configuration

**Files:** Create `lib/src/app/runtime_platform.dart`, `lib/src/features/distribution/domain/testflight_link.dart`, `lib/src/features/distribution/application/distribution_providers.dart`, `test/app/runtime_platform_test.dart`, and `test/distribution/testflight_link_test.dart`.

- [ ] Write a test that `detectRuntimePlatform(isAndroid: false, isIOS: true)` returns `AppRuntimePlatform.ios`; run `flutter test test/app/runtime_platform_test.dart` and observe the missing-library failure.
- [ ] Add `AppRuntimePlatform { android, ios, other }` and a detector with explicit test flags; rerun the test to PASS.
- [ ] Write tests accepting `https://testflight.apple.com/join/AbCdEf12` and rejecting `https://example.com/app.apk`; run `flutter test test/distribution/testflight_link_test.dart` and observe the missing-type failure.
- [ ] Add `TestFlightLink.parse(String)` and a Riverpod provider using `const String.fromEnvironment('TESTFLIGHT_URL')`; rerun both test files to PASS.

### Task 2: Distribution surface

**Files:** Modify `lib/src/features/statistics/presentation/statistics_screen.dart` and `test/statistics/statistics_screen_test.dart`.

- [ ] Add failing widget tests showing an iOS share sheet has neither `Key('share-android')` nor TestFlight when no link exists, and has only `Key('share-ios-testflight')` when one exists.
- [ ] Run the focused widget test to confirm the present unconditional Android row fails it.
- [ ] Consume the Task 1 providers, preserve Android QR creation solely on Android, and use `url_launcher` only for a configured iOS TestFlight link.
- [ ] Run `flutter test test/statistics/statistics_screen_test.dart` to PASS.

### Task 3: iOS notifications

**Files:** Modify `lib/src/features/reminder/daily_task_reminder.dart` and `test/reminder/daily_task_reminder_test.dart`.

- [ ] Add a failing test for iOS initialization selecting `DarwinInitializationSettings`.
- [ ] Add minimal injected platform support, iOS permission request, and `DarwinNotificationDetails`; leave exact-alarm checks and `AndroidScheduleMode.exactAllowWhileIdle` in Android-only branches.
- [ ] Run `flutter test test/reminder/daily_task_reminder_test.dart` to PASS.

### Task 4: Disable APK updater on iOS

**Files:** Modify `lib/src/app/app.dart`, `lib/src/features/update/application/update_providers.dart`, and their existing tests.

- [ ] Add a failing test that an iOS `autoCheck` does not read the APK feed.
- [ ] Add explicit iOS platform identity, and guard the launch timer and update check unless Android.
- [ ] Run `flutter test test/update/update_controller_test.dart test/update/about_screen_test.dart` to PASS.

### Task 5: Apple configuration and release checks

**Files:** Modify `ios/Runner/Info.plist`, `test/app/platform_configuration_test.dart`, `.github/workflows/android-apk.yml`, and `README.md`.

- [ ] Add a failing test for display name `圣经背诵` and `NSMicrophoneUsageDescription`.
- [ ] Add plist values; add `flutter test` before the existing iOS simulator CI build; document `--dart-define=TESTFLIGHT_URL=https://testflight.apple.com/join/<code>` for a future signed archive.
- [ ] Run `dart format`, `flutter analyze`, `flutter test`, `flutter build apk --release`, and `flutter build ios --simulator --debug`.

## Release handoff

After Apple Developer Program enrollment, sign the Runner target in Xcode, archive/upload it to App Store Connect, submit the first external build for TestFlight review, configure the approved public link, and validate device-only behavior with an invited iPhone tester.

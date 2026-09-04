# iOS/TestFlight Adaptation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an iPhone-compatible build named 圣经背诵 while preserving Android APK behavior and preparing a future TestFlight distribution path.

**Architecture:** Keep app features in the shared Flutter layer and represent the runtime platform explicitly where UI and startup behavior differ. Android update, APK QR, and MediaStore integrations remain Android-only; iOS uses built-in document save UI, Darwin local-notification configuration, Apple privacy declarations, and later a supplied TestFlight URL.

**Tech Stack:** Flutter 3.44.4, Dart, Riverpod, `flutter_local_notifications`, `file_selector`, Xcode 26.6, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-04-ios-testflight-design.md`

## Global Constraints

- iOS display name is exactly `圣经背诵` and minimum deployment target is iOS 13.0.
- The bundle identifier remains `app.biblerecite` unless the Apple account reports it unavailable.
- Android APK update, QR, MediaStore, and exact-alarm behavior must remain unchanged.
- iOS must not display or save the Android APK QR; TestFlight UI is hidden until a valid HTTPS public link is configured.
- New behavioral code is introduced by a failing Dart/Flutter test before its implementation.
- Flutter 3.44.4 must be available locally before running build commands.

---

## File structure

- `lib/src/app/runtime_platform.dart` — immutable platform identity and test override seam.
- `lib/src/features/distribution/domain/testflight_link.dart` — validates the optional public TestFlight URL and defines when iOS distribution UI is available.
- `lib/src/features/distribution/application/distribution_providers.dart` — reads the compile-time TestFlight URL without hard-coding a link in source control.
- `lib/src/features/statistics/presentation/statistics_screen.dart` — shows Android QR only on Android and an iOS TestFlight action only when configured.
- `lib/src/features/reminder/daily_task_reminder.dart` — creates Android or Darwin notification settings while sharing slot calculation and persistence.
- `lib/src/app/app.dart` — avoids the Android-only update timer and update check outside Android.
- `ios/Runner/Info.plist` — display name and microphone privacy description.
- `test/app/runtime_platform_test.dart`, `test/distribution/testflight_link_test.dart`, `test/statistics/statistics_screen_test.dart`, `test/reminder/daily_task_reminder_test.dart`, `test/app/platform_configuration_test.dart` — regression coverage.
- `.github/workflows/android-apk.yml` — retains Android release stages and verifies the iOS simulator artifact after the changed app configuration.

### Task 1: Make runtime platform and TestFlight configuration testable

**Files:**
- Create: `lib/src/app/runtime_platform.dart`
- Create: `lib/src/features/distribution/domain/testflight_link.dart`
- Create: `lib/src/features/distribution/application/distribution_providers.dart`
- Create: `test/app/runtime_platform_test.dart`
- Create: `test/distribution/testflight_link_test.dart`

**Interfaces:**
- Produces `enum AppRuntimePlatform { android, ios, other }` and `AppRuntimePlatform detectRuntimePlatform({bool? isAndroid, bool? isIOS})`.
- Produces `TestFlightLink? TestFlightLink.parse(String raw)` where `url` is an HTTPS URI hosted by `testflight.apple.com`.
- Produces `Provider<TestFlightLink?> testFlightLinkProvider` backed by `String.fromEnvironment('TESTFLIGHT_URL')`.

- [ ] **Step 1: Write failing platform detection tests**

```dart
test('reports iOS when the iOS platform flag is set', () {
  expect(
    detectRuntimePlatform(isAndroid: false, isIOS: true),
    AppRuntimePlatform.ios,
  );
});
```

- [ ] **Step 2: Run the test and verify it fails because the library does not exist**

Run: `flutter test test/app/runtime_platform_test.dart`

Expected: FAIL with an import or undefined-symbol error for `runtime_platform.dart`.

- [ ] **Step 3: Add the minimal runtime platform implementation**

```dart
enum AppRuntimePlatform { android, ios, other }

AppRuntimePlatform detectRuntimePlatform({bool? isAndroid, bool? isIOS}) {
  if (isAndroid ?? Platform.isAndroid) return AppRuntimePlatform.android;
  if (isIOS ?? Platform.isIOS) return AppRuntimePlatform.ios;
  return AppRuntimePlatform.other;
}
```

- [ ] **Step 4: Run the platform test and verify it passes**

Run: `flutter test test/app/runtime_platform_test.dart`

Expected: PASS.

- [ ] **Step 5: Write failing TestFlight URL tests**

```dart
test('accepts an HTTPS TestFlight public link', () {
  final link = TestFlightLink.parse('https://testflight.apple.com/join/AbCdEf12');
  expect(link?.url.host, 'testflight.apple.com');
});

test('rejects an APK or arbitrary HTTPS link', () {
  expect(TestFlightLink.parse('https://example.com/app.apk'), isNull);
});
```

- [ ] **Step 6: Run the TestFlight URL test and verify it fails because the type does not exist**

Run: `flutter test test/distribution/testflight_link_test.dart`

Expected: FAIL with an import or undefined-symbol error for `TestFlightLink`.

- [ ] **Step 7: Add the minimal value object and provider**

```dart
final class TestFlightLink {
  const TestFlightLink._(this.url);
  final Uri url;

  static TestFlightLink? parse(String raw) {
    final url = Uri.tryParse(raw.trim());
    if (url == null || url.scheme != 'https' || url.host != 'testflight.apple.com') return null;
    return TestFlightLink._(url);
  }
}
```

Use `TestFlightLink.parse(const String.fromEnvironment('TESTFLIGHT_URL'))` as the provider value.

- [ ] **Step 8: Run both new tests and commit**

Run: `flutter test test/app/runtime_platform_test.dart test/distribution/testflight_link_test.dart`

Expected: PASS.

Commit: `git add lib/src/app/runtime_platform.dart lib/src/features/distribution test/app/runtime_platform_test.dart test/distribution/testflight_link_test.dart && git commit -m "feat: add TestFlight distribution configuration"`

### Task 2: Keep distribution UI correct per platform

**Files:**
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart:45-85,700-845`
- Modify: `test/statistics/statistics_screen_test.dart`

**Interfaces:**
- Consumes `AppRuntimePlatform` and `testFlightLinkProvider` from Task 1.
- Produces a share sheet with the existing Android QR row only on Android and a `Key('share-ios-testflight')` row only when the runtime is iOS and a valid link exists.

- [ ] **Step 1: Write a failing widget test for hidden iOS TestFlight UI without a link**

```dart
testWidgets('does not offer iOS distribution before a TestFlight link exists', (tester) async {
  await pumpStatistics(tester, platform: AppRuntimePlatform.ios, testFlightLink: null);
  await tester.tap(find.byKey(const Key('share-platforms')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('share-ios-testflight')), findsNothing);
  expect(find.byKey(const Key('share-android')), findsNothing);
});
```

- [ ] **Step 2: Run the widget test and verify it fails because the screen has no platform injection**

Run: `flutter test test/statistics/statistics_screen_test.dart --plain-name "does not offer iOS distribution before a TestFlight link exists"`

Expected: FAIL because the current sheet always renders Android and disabled iOS rows.

- [ ] **Step 3: Implement the minimal platform branches**

Use providers rather than `Platform.isIOS` inside the widget so the test overrides the runtime. Render the existing Android QR row only for Android. On iOS render a `ListTile` with key `share-ios-testflight`, title `TestFlight`, and a user-initiated `url_launcher` call only when `testFlightLinkProvider` is non-null. Do not add a Photos permission, QR save channel, or QR widget to the iOS path.

- [ ] **Step 4: Add and run the complementary valid-link widget test**

```dart
expect(find.byKey(const Key('share-ios-testflight')), findsOneWidget);
expect(find.byKey(const Key('share-android')), findsNothing);
```

Run: `flutter test test/statistics/statistics_screen_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Commit: `git add lib/src/features/statistics/presentation/statistics_screen.dart test/statistics/statistics_screen_test.dart && git commit -m "feat: add iOS TestFlight distribution entry"`

### Task 3: Add iOS local-notification behavior without changing Android alarms

**Files:**
- Modify: `lib/src/features/reminder/daily_task_reminder.dart:35-125`
- Modify: `test/reminder/daily_task_reminder_test.dart`

**Interfaces:**
- Consumes `AppRuntimePlatform` from Task 1.
- Produces `DailyTaskReminderScheduler({..., AppRuntimePlatform? platform})` that uses Android exact alarms only on Android and Darwin initialization/details on iOS.

- [ ] **Step 1: Write a failing construction test for iOS reminder configuration**

```dart
test('creates Darwin notification initialization settings for iOS', () {
  final scheduler = DailyTaskReminderScheduler(platform: AppRuntimePlatform.ios);
  expect(scheduler.initializationSettings.ios, isA<DarwinInitializationSettings>());
});
```

- [ ] **Step 2: Run the test and verify it fails because the platform constructor argument and settings getter do not exist**

Run: `flutter test test/reminder/daily_task_reminder_test.dart --plain-name "creates Darwin notification initialization settings for iOS"`

Expected: FAIL with a missing named parameter or getter.

- [ ] **Step 3: Implement the smallest injectable platform split**

Build `InitializationSettings` with Android settings only for Android and `DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true)` for iOS. On iOS call the Darwin plugin permission request and schedule `DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true)`. Leave `canScheduleExactNotifications` and `AndroidScheduleMode.exactAllowWhileIdle` inside the Android branch.

- [ ] **Step 4: Run reminder tests and verify Android slot semantics remain unchanged**

Run: `flutter test test/reminder/daily_task_reminder_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Commit: `git add lib/src/features/reminder/daily_task_reminder.dart test/reminder/daily_task_reminder_test.dart && git commit -m "feat: configure reminders for iOS"`

### Task 4: Suppress Android-only update activity on iOS

**Files:**
- Modify: `lib/src/app/app.dart:20-130`
- Modify: `lib/src/features/update/application/update_providers.dart:18,91-95`
- Modify: `test/app/app_shell_test.dart`
- Modify: `test/update/update_controller_test.dart`

**Interfaces:**
- Consumes `AppRuntimePlatform` from Task 1.
- Produces no periodic update timer, update feed read, APK notification, or install entry when platform is iOS or other.

- [ ] **Step 1: Write a failing controller test for iOS update checks**

```dart
test('does not fetch APK updates on iOS', () async {
  final container = createContainer(runtimePlatform: AppRuntimePlatform.ios);
  await container.read(updateControllerProvider.notifier).autoCheck();
  expect(feedReadCount, 0);
});
```

- [ ] **Step 2: Run the test and verify it fails because iOS is currently represented as `other`**

Run: `flutter test test/update/update_controller_test.dart --plain-name "does not fetch APK updates on iOS"`

Expected: FAIL until the runtime platform enum and provider use the explicit iOS value.

- [ ] **Step 3: Implement the minimal update guard**

Replace `UpdateRuntimePlatform.other` with separate `ios` and `other` values, map the provider from `AppRuntimePlatform`, and return before startup update scheduling/checking unless the app runtime is Android. Preserve existing Android test expectations.

- [ ] **Step 4: Run update tests**

Run: `flutter test test/update/update_controller_test.dart test/update/about_screen_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

Commit: `git add lib/src/app/app.dart lib/src/features/update/application/update_providers.dart test/app/app_shell_test.dart test/update/update_controller_test.dart && git commit -m "fix: skip Android APK updates on iOS"`

### Task 5: Configure Apple metadata and build validation

**Files:**
- Modify: `ios/Runner/Info.plist`
- Modify: `test/app/platform_configuration_test.dart`
- Modify: `.github/workflows/android-apk.yml`
- Modify: `README.md:1-4,451-460`

**Interfaces:**
- Produces `CFBundleDisplayName` of `圣经背诵` and `NSMicrophoneUsageDescription` explaining offline recitation recording.
- Produces a simulator CI build that runs the shared test suite before packaging the iOS app.

- [ ] **Step 1: Write failing project-configuration tests**

```dart
test('iOS declares its display name and microphone reason', () {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();
  expect(plist, contains('<string>圣经背诵</string>'));
  expect(plist, contains('<key>NSMicrophoneUsageDescription</key>'));
});
```

- [ ] **Step 2: Run the test and verify it fails on the current English display name and missing privacy key**

Run: `flutter test test/app/platform_configuration_test.dart --plain-name "iOS declares its display name and microphone reason"`

Expected: FAIL.

- [ ] **Step 3: Add the minimal plist, CI, and README changes**

Set the display name to `圣经背诵`; add a Chinese microphone-use description that states recording is used for offline recitation checking; retain `app.biblerecite` and iOS 13. Add `flutter test` before the simulator build in the existing iOS GitHub Actions job. Update the README support statement to say iOS is in TestFlight preparation and explain `--dart-define=TESTFLIGHT_URL=https://testflight.apple.com/join/<code>` for the release build after Apple provides the public link.

- [ ] **Step 4: Run formatting, targeted tests, analysis, all tests, and both platform builds**

Run: `dart format lib/src/app lib/src/features/distribution lib/src/features/reminder lib/src/features/statistics test/app test/distribution test/reminder test/statistics`

Run: `flutter test test/app/platform_configuration_test.dart test/app/runtime_platform_test.dart test/distribution/testflight_link_test.dart test/reminder/daily_task_reminder_test.dart test/statistics/statistics_screen_test.dart`

Run: `flutter analyze`

Run: `flutter test`

Run: `flutter build apk --release`

Run: `flutter build ios --simulator --debug`

Expected: every command exits 0. If the local Flutter toolchain is unavailable, use the existing GitHub Actions workflow to obtain the equivalent Android and iOS simulator checks and report that device-only iOS checks are still pending.

- [ ] **Step 5: Commit**

Commit: `git add ios/Runner/Info.plist test/app/platform_configuration_test.dart .github/workflows/android-apk.yml README.md && git commit -m "chore: prepare iOS TestFlight build metadata"`

## Release handoff

After code validation, wait for Apple Developer Program enrollment. In Xcode, sign Runner with the individual account, archive with `--dart-define=TESTFLIGHT_URL=<approved-public-link>` only after the link exists, upload to App Store Connect, and use an iPhone TestFlight tester to accept microphone and notification permissions and validate recording, exports, and reminders.

# Android Auto Update and About Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a collapsible recent-recitation section, a cross-platform About page, and a secure Android updater that publishes through Cloudflare R2 with GitHub Release fallback.

**Architecture:** Keep update parsing, downloading, verification, orchestration, and presentation behind separate interfaces under `features/update`. Android-only package inspection and installation use one narrow method channel; release automation creates a signed update envelope and updates the R2 pointer only after validated artifacts exist.

**Tech Stack:** Flutter 3.44.4, Dart 3.12, Riverpod, GoRouter, `cryptography` 2.9.0, `package_info_plus` 9.0.1, `url_launcher` 6.3.2, `dart:io`, Kotlin/Android PackageManager and FileProvider, GitHub Actions, AWS CLI against Cloudflare R2.

## Global Constraints

- Android package name remains exactly `app.biblerecite`.
- Permanent APK certificate SHA-256 remains `4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7`.
- Never fall back to a new debug or per-run signing key.
- Open `/about` to check updates; do not show an update prompt during app startup.
- Only a signed protocol-1 feed may trigger a download.
- R2 is primary, GitHub Release is fallback; no third-party GitHub proxy.
- Android installation always goes through user-visible system confirmation.
- iOS, Windows, and macOS show version and Release link but never download an APK.
- Wi-Fi download starts after the user taps update; mobile transport requires a size confirmation.
- R2 keeps the newest 10 APKs; GitHub Releases remain permanent.
- `versionName` is compared first; equal names compare `buildNumber`.
- Every cloud build for a new commit receives a monotonically increasing effective build.
- APK filenames continue to start with `BibleRecite-`.
- Every task uses TDD and ends with a focused commit.

---

## File Map

**Create:**

- `lib/src/features/update/domain/app_version.dart` — semantic version and build comparison.
- `lib/src/features/update/domain/update_manifest.dart` — signed envelope and validated payload models.
- `lib/src/features/update/domain/update_status.dart` — controller states and download progress.
- `lib/src/features/update/data/update_feed_client.dart` — source fallback and Ed25519 verification.
- `lib/src/features/update/data/resumable_downloader.dart` — `.part` metadata, Range/ETag, cancellation and URL fallback.
- `lib/src/features/update/data/update_verifier.dart` — size and SHA-256 verification plus Android bridge delegation.
- `lib/src/features/update/data/update_signing_public_key.dart` — generated Ed25519 public key only.
- `lib/src/features/update/application/update_controller.dart` — update state machine.
- `lib/src/features/update/application/update_providers.dart` — production Riverpod wiring and test overrides.
- `lib/src/features/update/platform/android_update_bridge.dart` — Dart method-channel wrapper.
- `lib/src/features/update/presentation/about_screen.dart` — About/update UI.
- `android/app/src/main/kotlin/app/biblerecite/AppUpdateChannel.kt` — package inspection, permission and installer intents.
- `android/app/src/main/res/xml/update_file_paths.xml` — FileProvider path allowlist.
- `tool/update_feed/bin/resolve_build.dart` — deterministic effective build selection.
- `tool/update_feed/bin/create_update_envelope.dart` — payload creation and Ed25519 signing.
- `tool/update_feed/bin/generate_update_key.dart` — one-time key generation into explicit private/public output files.
- `test/update/app_version_test.dart`
- `test/update/update_manifest_test.dart`
- `test/update/update_feed_client_test.dart`
- `test/update/resumable_downloader_test.dart`
- `test/update/update_controller_test.dart`
- `test/update/about_screen_test.dart`
- `tool/update_feed/test/resolve_build_test.dart`
- `tool/update_feed/test/create_update_envelope_test.dart`
- `tool/update_feed/test/generate_update_key_test.dart`

**Modify:**

- `pubspec.yaml` — add compatible package metadata/browser dependencies.
- `lib/src/app/router.dart` — register `/about`.
- `lib/src/app/responsive_shell.dart` — keep the “我的” destination selected on `/about`.
- `lib/src/features/statistics/presentation/statistics_screen.dart` — recent record folding and About card.
- `lib/src/features/plans/data/sqlite_plan_repository.dart` — offset pagination.
- `android/app/src/main/kotlin/app/biblerecite/MainActivity.kt` — register update channel.
- `android/app/src/main/AndroidManifest.xml` — install permission and FileProvider.
- `.github/workflows/android-apk.yml` — effective build, signed feed, R2 upload and retention.
- `tool/build_versioned_apk.ps1` — explicit safe build selection.
- `test/statistics/statistics_repository_test.dart`
- `test/statistics/statistics_screen_test.dart`
- `test/app/app_navigation_test.dart`
- `test/app/app_shell_test.dart`
- `test/app/platform_configuration_test.dart`

---

### Task 1: Version Domain and Signed Manifest Models

**Files:**
- Create: `lib/src/features/update/domain/app_version.dart`
- Create: `lib/src/features/update/domain/update_manifest.dart`
- Create: `test/update/app_version_test.dart`
- Create: `test/update/update_manifest_test.dart`

**Interfaces:**
- Produces: `AppVersion.parse(String versionName, String buildNumber)`, `bool AppVersion.isNewerThan(AppVersion other)`.
- Produces: `SignedUpdateEnvelope.decode(List<int> bytes)` and `UpdateManifest.fromPayloadBytes(List<int> bytes)`.

- [ ] **Step 1: Write failing version-order tests**

```dart
test('semantic version wins before build number', () {
  final local = AppVersion.parse('1.0.4', '20');
  expect(AppVersion.parse('1.0.5', '1').isNewerThan(local), isTrue);
  expect(AppVersion.parse('1.0.3', '99').isNewerThan(local), isFalse);
  expect(AppVersion.parse('1.0.4', '21').isNewerThan(local), isTrue);
  expect(AppVersion.parse('1.0.4', '20').isNewerThan(local), isFalse);
});

test('rejects non numeric semantic versions and builds', () {
  expect(() => AppVersion.parse('1.0-beta', '2'), throwsFormatException);
  expect(() => AppVersion.parse('1.0.0', '2a'), throwsFormatException);
});
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\app_version_test.dart`

Expected: FAIL because `app_version.dart` and `AppVersion` do not exist.

- [ ] **Step 3: Implement immutable version comparison**

```dart
final class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this.major, this.minor, this.patch, this.buildNumber);
  final int major;
  final int minor;
  final int patch;
  final int buildNumber;

  factory AppVersion.parse(String name, String build) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(name);
    final parsedBuild = int.tryParse(build);
    if (match == null || parsedBuild == null || parsedBuild < 0) {
      throw const FormatException('Invalid application version');
    }
    return AppVersion._(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      parsedBuild,
    );
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  int compareTo(AppVersion other) {
    for (final pair in [(major, other.major), (minor, other.minor),
      (patch, other.patch), (buildNumber, other.buildNumber)]) {
      final value = pair.$1.compareTo(pair.$2);
      if (value != 0) return value;
    }
    return 0;
  }
}
```

- [ ] **Step 4: Write failing signed-envelope validation tests**

Test exact protocol, Base64 decoding, required Android asset fields, HTTPS URLs, `app.biblerecite`, nonnegative size, 64-character lowercase SHA-256 and the fixed certificate. Use fixture payload bytes and assert malformed fields throw `FormatException`.

```dart
final envelope = SignedUpdateEnvelope.decode(utf8.encode(jsonEncode({
  'protocol': 1,
  'payload': base64Encode(payloadBytes),
  'signature': base64Encode(List<int>.filled(64, 1)),
})));
expect(envelope.protocol, 1);
expect(envelope.payloadBytes, payloadBytes);
expect(UpdateManifest.fromPayloadBytes(payloadBytes).android.packageName,
    'app.biblerecite');
```

- [ ] **Step 5: Implement exact manifest models and rerun both tests**

Define `SignedUpdateEnvelope`, `UpdateManifest`, and `AndroidUpdateAsset` with final fields and strict factories. Do not accept missing fields, HTTP URLs, more than two download URLs, or a file not matching `^BibleRecite-.+\.apk$`.

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\app_version_test.dart test\update\update_manifest_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/src/features/update/domain test/update/app_version_test.dart test/update/update_manifest_test.dart
git commit -m "feat: add signed update manifest domain"
```

### Task 2: Signed Feed Verification and Source Fallback

**Files:**
- Create: `lib/src/features/update/data/update_feed_client.dart`
- Create: `test/update/update_feed_client_test.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: `SignedUpdateEnvelope`, `UpdateManifest` from Task 1.
- Produces: `UpdateFeedClient.fetchLatest(): Future<UpdateManifest>`.

- [ ] **Step 1: Add compatible runtime dependencies**

Add exact constraints:

```yaml
package_info_plus: 9.0.1
url_launcher: 6.3.2
```

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat pub get`

Expected: dependencies resolve without changing Flutter or Android Gradle versions.

- [ ] **Step 2: Write failing feed tests with a fake transport**

Define this seam in the test and production file:

```dart
abstract interface class UpdateBytesTransport {
  Future<List<int>> get(Uri uri);
}
```

Cover primary success, primary exception followed by secondary success, all sources failing, invalid signature, and signed payload parsing. Sign fixtures with `Ed25519().newKeyPairFromSeed(List<int>.generate(32, (i) => i))`.

- [ ] **Step 3: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\update_feed_client_test.dart`

Expected: FAIL because `UpdateFeedClient` is missing.

- [ ] **Step 4: Implement feed fallback and raw-byte Ed25519 verification**

```dart
final class UpdateFeedClient {
  const UpdateFeedClient({
    required this.sources,
    required this.transport,
    required this.publicKey,
  });
  final List<Uri> sources;
  final UpdateBytesTransport transport;
  final SimplePublicKey publicKey;

  Future<UpdateManifest> fetchLatest() async {
    final failures = <String>[];
    for (final source in sources) {
      try {
        final envelope = SignedUpdateEnvelope.decode(await transport.get(source));
        final valid = await Ed25519().verify(
          envelope.payloadBytes,
          signature: Signature(envelope.signatureBytes, publicKey: publicKey),
        );
        if (!valid) throw const FormatException('Invalid update signature');
        return UpdateManifest.fromPayloadBytes(envelope.payloadBytes);
      } catch (error) {
        failures.add('${source.host}: $error');
      }
    }
    throw UpdateFeedException(List.unmodifiable(failures));
  }
}
```

Production sources are R2, `gcore.jsdelivr.net`, `fastly.jsdelivr.net`, `cdn.jsdelivr.net`, then GitHub Raw for the signed feed only. The APK URL list remains R2 then GitHub Release.

Use these exact non-R2 feed fallbacks:

```dart
const updateFeedFallbacks = [
  'https://gcore.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
  'https://fastly.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
  'https://cdn.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
  'https://raw.githubusercontent.com/kobe24o/bible_recite/update-feed/updates/latest.json',
];
```

- [ ] **Step 5: Generate the permanent update-feed key safely**

Add `generate_update_key.dart` and its test in this task. It accepts `--private-output` and `--public-output`, creates a 32-byte Ed25519 seed, writes Base64 values without printing the private value, and refuses to overwrite either path. Generate into a new directory under `C:\tmp`, pipe the private file to `gh secret set UPDATE_MANIFEST_PRIVATE_KEY`, create `update_signing_public_key.dart` from the public file, then remove only that exact temporary directory after resolving and checking it is under `C:\tmp`. Commit only the public key.

- [ ] **Step 6: Run tests and commit**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\update_feed_client_test.dart tool\update_feed\test\generate_update_key_test.dart`

Expected: PASS.

```powershell
git add pubspec.yaml pubspec.lock lib/src/features/update/data/update_feed_client.dart lib/src/features/update/data/update_signing_public_key.dart tool/update_feed/bin/generate_update_key.dart tool/update_feed/test/generate_update_key_test.dart test/update/update_feed_client_test.dart
git commit -m "feat: verify signed update feeds"
```

### Task 3: Resumable APK Downloader and Integrity Verification

**Files:**
- Create: `lib/src/features/update/data/resumable_downloader.dart`
- Create: `lib/src/features/update/data/update_verifier.dart`
- Create: `test/update/resumable_downloader_test.dart`

**Interfaces:**
- Produces: `DownloadProgress`, `DownloadedUpdate`, `DownloadCancellation`.
- Produces: `ResumableDownloader.download(AndroidUpdateAsset asset, Directory directory, {required void Function(DownloadProgress) onProgress, required DownloadCancellation cancellation})`.
- Produces: `UpdateVerifier.verifyFile(File file, AndroidUpdateAsset asset)`.

- [ ] **Step 1: Write failing local-server download tests**

Use `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` to serve deterministic bytes. Test a full `200`, resumed `206` with `Range`, changed ETag forcing restart, R2 `500` followed by GitHub success, cancellation retaining `.part`, and wrong Content-Range rejection.

```dart
final result = await downloader.download(
  asset,
  tempDirectory,
  onProgress: progress.add,
  cancellation: DownloadCancellation(),
);
expect(await result.file.readAsBytes(), payload);
expect(progress.last.receivedBytes, payload.length);
```

- [ ] **Step 2: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\resumable_downloader_test.dart`

Expected: FAIL because downloader types are missing.

- [ ] **Step 3: Implement streaming download without loading the APK into memory**

Use `HttpClient`, `IOSink`, a sidecar JSON file containing URL/ETag/expected size/received bytes, and a fixed 15-second connect timeout. Validate status `200` or `206` and exact Content-Range start. On source failure close handles before trying the next URL. Rename `.part` to `.apk` only after exact expected byte count.

- [ ] **Step 4: Add SHA-256 verification tests and implementation**

Use `cryptography` streaming hash:

```dart
final sink = Sha256().newHashSink();
await for (final chunk in file.openRead()) {
  sink.add(chunk);
}
sink.close();
final digest = await sink.hash();
if (hexFromBytes(digest.bytes) != asset.sha256) {
  throw const UpdateVerificationException('sha256_mismatch');
}
```

Check expected size before hashing. A failed check deletes final and partial files.

- [ ] **Step 5: Run tests and commit**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\resumable_downloader_test.dart`

Expected: PASS, including cancellation and fallback cases.

```powershell
git add lib/src/features/update/data/resumable_downloader.dart lib/src/features/update/data/update_verifier.dart test/update/resumable_downloader_test.dart
git commit -m "feat: add resumable verified APK downloads"
```

### Task 4: Android APK Inspection and System Installer Bridge

**Files:**
- Create: `lib/src/features/update/platform/android_update_bridge.dart`
- Create: `android/app/src/main/kotlin/app/biblerecite/AppUpdateChannel.kt`
- Create: `android/app/src/main/res/xml/update_file_paths.xml`
- Modify: `android/app/src/main/kotlin/app/biblerecite/MainActivity.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `test/app/platform_configuration_test.dart`

**Interfaces:**
- Produces: `AndroidApkInfo(packageName, versionName, versionCode, certificateSha256)`.
- Produces: `inspectApk`, `canRequestPackageInstalls`, `openInstallPermission`, `installApk`, and `networkTransport` method-channel calls.

- [ ] **Step 1: Extend configuration tests first**

Assert the main manifest contains `android.permission.REQUEST_INSTALL_PACKAGES`, a non-exported `androidx.core.content.FileProvider`, `${applicationId}.update-files`, and `@xml/update_file_paths`. Assert the XML exposes only the named update cache subdirectory.

- [ ] **Step 2: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\app\platform_configuration_test.dart`

Expected: FAIL on missing install configuration.

- [ ] **Step 3: Implement the Kotlin channel**

Register `app.biblerecite/update` from `MainActivity.configureFlutterEngine`. Implement:

```kotlin
when (call.method) {
    "inspectApk" -> result.success(inspectApk(requirePath(call)))
    "canRequestPackageInstalls" -> result.success(
        Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()
    )
    "openInstallPermission" -> openInstallPermission(result)
    "installApk" -> installApk(requirePath(call), result)
    "networkTransport" -> result.success(networkTransport())
    else -> result.notImplemented()
}
```

For API 28+, inspect `PackageInfo.signingInfo.apkContentsSigners`; for API 24–27 use deprecated `signatures`. Hash the DER certificate bytes with SHA-256 and lowercase hex. Use `Intent.ACTION_MANAGE_UNKNOWN_APP_SOURCES` and `Intent.ACTION_INSTALL_PACKAGE` with `FLAG_GRANT_READ_URI_PERMISSION`.

- [ ] **Step 4: Implement the Dart wrapper and verifier integration**

`UpdateVerifier.verifyAndroidPackage` must compare all four fields with the signed manifest and require the remote `AppVersion` to be newer than installed.

- [ ] **Step 5: Run tests, build debug Android, and commit**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\app\platform_configuration_test.dart
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat build apk --debug
```

Expected: test PASS and debug APK build succeeds.

```powershell
git add android/app/src/main lib/src/features/update/platform lib/src/features/update/data/update_verifier.dart test/app/platform_configuration_test.dart
git commit -m "feat: add secure Android update installer bridge"
```

### Task 5: Update Controller and Production Providers

**Files:**
- Create: `lib/src/features/update/domain/update_status.dart`
- Create: `lib/src/features/update/application/update_controller.dart`
- Create: `lib/src/features/update/application/update_providers.dart`
- Create: `test/update/update_controller_test.dart`

**Interfaces:**
- Produces: `UpdateStatus` sealed states: idle, checking, current, available, awaitingCellularConfirmation, downloading, readyToInstall, permissionRequired, installing, failed.
- Produces: `UpdateController.check`, `startDownload`, `confirmCellularDownload`, `cancelDownload`, and `install`.

- [ ] **Step 1: Write state-machine tests with fakes**

Cover check current/new/error, mobile confirmation, Wi-Fi direct download, progress, cancellation, verification failure, permission redirect, return-from-settings install, and non-Android Release-link behavior.

```dart
await controller.check();
expect(controller.state, isA<UpdateAvailable>());
await controller.startDownload();
expect(controller.state, isA<AwaitingCellularConfirmation>());
await controller.confirmCellularDownload();
expect(controller.state, isA<ReadyToInstall>());
```

- [ ] **Step 2: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\update_controller_test.dart`

Expected: FAIL because controller and states are missing.

- [ ] **Step 3: Implement serialized controller transitions**

Reject a second check/download while one is active. Store one cancellation object per download. After Android settings returns, call `canRequestPackageInstalls` again; never assume permission was granted. Map technical failures to stable reason codes and keep raw exceptions out of user-facing text.

- [ ] **Step 4: Wire Riverpod providers**

Use `PackageInfo.fromPlatform()` for installed version, `getApplicationSupportDirectory()/updates` for files, the embedded Ed25519 public key, and the production feed candidate list. Expose each dependency as a provider so widget tests can override it.

- [ ] **Step 5: Run tests and commit**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\update_controller_test.dart`

Expected: PASS.

```powershell
git add lib/src/features/update/application lib/src/features/update/domain/update_status.dart test/update/update_controller_test.dart
git commit -m "feat: orchestrate app update states"
```

### Task 6: About Page and Navigation

**Files:**
- Create: `lib/src/features/update/presentation/about_screen.dart`
- Create: `test/update/about_screen_test.dart`
- Modify: `lib/src/app/router.dart`
- Modify: `lib/src/app/responsive_shell.dart`
- Modify: `test/app/app_navigation_test.dart`
- Modify: `test/app/app_shell_test.dart`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify (generated): `lib/l10n/generated/app_localizations.dart`
- Modify (generated): `lib/l10n/generated/app_localizations_en.dart`
- Modify (generated): `lib/l10n/generated/app_localizations_zh.dart`

**Interfaces:**
- Consumes: `updateControllerProvider` and `PackageInfo` provider from Task 5.
- Produces: route `/about` and keys `about-check`, `about-update`, `about-cancel`, `about-install`, `about-release-link`.

- [ ] **Step 1: Write failing About widget tests**

Test automatic check after first frame, `1.0.4（构建 7）`, latest, available with size/notes, progress/cancel, cellular dialog, failure/retry, permission instruction, Android install, and non-Android Release link.

- [ ] **Step 2: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\about_screen_test.dart`

Expected: FAIL because `AboutScreen` is missing.

- [ ] **Step 3: Implement About UI from controller states**

Call `check()` exactly once from `initState` via `addPostFrameCallback`. Use determinate progress when total size is known. Format bytes and speed locally. Do not invoke download merely by opening the page.

- [ ] **Step 4: Add `/about` route and localization**

Register `AboutScreen` in `router.dart`; add localized strings in all three ARB files and run `flutter gen-l10n`. Update `ResponsiveShell.selectedIndex` so `/about` maps to index 3 while `/about/scripture-sources` remains index 1. Navigation and shell tests must open `/about` without changing the selected “我的” destination.

- [ ] **Step 5: Run tests and commit**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat gen-l10n
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\update\about_screen_test.dart test\app\app_navigation_test.dart test\app\app_shell_test.dart
```

Expected: PASS.

```powershell
git add lib/src/features/update/presentation lib/src/app/router.dart lib/src/app/responsive_shell.dart lib/l10n test/update/about_screen_test.dart test/app/app_navigation_test.dart test/app/app_shell_test.dart
git commit -m "feat: add About and update UI"
```

### Task 7: Fold and Page Recent Recitations

**Files:**
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Modify: `test/statistics/statistics_repository_test.dart`
- Modify: `test/statistics/statistics_screen_test.dart`

**Interfaces:**
- Produces: `listRecitationResults({int limit = 50, int offset = 0})`.
- Consumes: `/about` route from Task 6.

- [ ] **Step 1: Write repository pagination tests**

Insert 13 timestamped results, request `limit: 10, offset: 0` and `limit: 10, offset: 10`, and assert IDs are newest-first with no overlap.

- [ ] **Step 2: Write widget tests for 10/11/large result sets**

Assert 10 cards and no expand for 10 records; 10 cards plus `展开全部（共 11 条）` for 11; after tap all 11 are visible and `收起` appears; after收起 only 10 remain. Assert the About card exists with zero records and navigates to `/about` through an injected callback/router.

- [ ] **Step 3: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\statistics\statistics_repository_test.dart test\statistics\statistics_screen_test.dart`

Expected: FAIL on missing offset and folding controls.

- [ ] **Step 4: Implement offset query and stateful recent section**

Change SQL to `LIMIT ? OFFSET ?`. Split `_RecentRecitationsSection` into a focused `StatefulWidget` that initially receives 10 rows and total count, fetches pages of 50 on expansion, and uses a lazy list/sliver rather than building every card in the parent `Column`.

- [ ] **Step 5: Add About card after recent records**

The card is outside the `hasStatistics` conditional and uses `context.push('/about')`; it must remain visible in empty state.

- [ ] **Step 6: Run tests and commit**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\statistics\statistics_repository_test.dart test\statistics\statistics_screen_test.dart`

Expected: PASS.

```powershell
git add lib/src/features/plans/data/sqlite_plan_repository.dart lib/src/features/statistics/presentation/statistics_screen.dart test/statistics
git commit -m "feat: fold recent recitations and link About"
```

### Task 8: Build Number Resolver and Signed Feed Tooling

**Files:**
- Create: `tool/update_feed/bin/resolve_build.dart`
- Create: `tool/update_feed/bin/create_update_envelope.dart`
- Create: `tool/update_feed/test/resolve_build_test.dart`
- Create: `tool/update_feed/test/create_update_envelope_test.dart`

**Interfaces:**
- Produces: `resolveEffectiveBuild(pubspecBuild, runNumber, latestManifest, sourceCommit)`.
- Produces: CLI envelope bytes identical for identical payload/key inputs.

- [ ] **Step 1: Write resolver tests**

Cover first release, new commit using maximum plus one, same latest `sourceCommit` reusing its build, versionName rollback rejection, and same version/build rejection.

```dart
expect(resolveEffectiveBuild(
  pubspecBuild: 5, runNumber: 9, latestBuild: 12,
  latestCommit: 'old', sourceCommit: 'new'), 13);
expect(resolveEffectiveBuild(
  pubspecBuild: 5, runNumber: 9, latestBuild: 12,
  latestCommit: 'same', sourceCommit: 'same'), 12);
```

- [ ] **Step 2: Implement resolver and CLI output**

The CLI writes `version_name`, `build_number`, and `source_commit` to the file passed by `--github-output`. It accepts a missing latest manifest for first release, verifies an existing envelope with the `--public-key` Base64 Ed25519 public key, and rejects malformed or unsigned existing data.

- [ ] **Step 3: Write and implement envelope signing-tool tests**

Create a deterministic 32-byte seed fixture, sign exact UTF-8 payload bytes with `Ed25519`, decode the produced envelope, and verify the signature. `create_update_envelope.dart` reads the private Base64 seed from `UPDATE_MANIFEST_PRIVATE_KEY`, never prints it, and writes only the signed envelope to the explicit `--output` path.

- [ ] **Step 4: Run tooling tests and commit**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\dart.bat test tool\update_feed\test`

Expected: PASS.

```powershell
git add tool/update_feed
git commit -m "feat: add signed update feed tooling"
```

### Task 9: Extend GitHub Actions for Effective Builds and R2

**Files:**
- Modify: `.github/workflows/android-apk.yml`
- Modify: `test/app/platform_configuration_test.dart`

**Interfaces:**
- Consumes: tooling from Task 8 and existing signing secrets.
- Produces: validated GitHub Release, R2 APK, signed `update-feed` branch manifest and R2 `updates/latest.json`.

- [ ] **Step 1: Write workflow configuration assertions first**

Assert workflow references all six R2/update secrets, `--build-number`, `create_update_envelope.dart`, `aws s3 cp`, `update-feed`, `Cache-Control`, fixed certificate, and cleanup retention count 10.

- [ ] **Step 2: Run and verify failure**

Run: `D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\app\platform_configuration_test.dart`

Expected: FAIL on missing R2/feed strings.

- [ ] **Step 3: Add a metadata job before platform builds**

Checkout with `fetch-depth: 0`, fetch R2 `updates/latest.json` when present, run the resolver, and expose `version_name` and `build_number` as job outputs. Android uses:

```bash
flutter build apk --release \
  --build-name "$VERSION_NAME" \
  --build-number "$BUILD_NUMBER"
```

iOS uses the same name/build with `--no-codesign`. Artifact names become `BibleRecite-${VERSION_NAME}+${BUILD_NUMBER}.apk` and `BibleRecite-iOS-${VERSION_NAME}+${BUILD_NUMBER}-unsigned.ipa`.

- [ ] **Step 4: Add publish ordering and R2 upload**

After checksum and fixed-certificate verification: create GitHub Release, configure AWS credentials through environment variables, upload immutable APK, build signed envelope, push the same envelope to `update-feed`, then upload R2 `updates/latest.json` with a short cache policy. Use versioned objects with `public,max-age=31536000,immutable` and latest with `public,max-age=300,must-revalidate`.

- [ ] **Step 5: Add retention and failure behavior**

List `android/` version prefixes by last modified time and delete only APK objects beyond the newest 10 after the latest pointer succeeds. Cleanup failure emits `::warning::` but upload/feed failures exit nonzero.

- [ ] **Step 6: Validate YAML and run tests**

Run:

```powershell
python -c "import yaml, pathlib; yaml.load(pathlib.Path('.github/workflows/android-apk.yml').read_text(encoding='utf-8'), Loader=yaml.BaseLoader); print('workflow yaml ok')"
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\app\platform_configuration_test.dart
```

Expected: `workflow yaml ok` and tests PASS.

- [ ] **Step 7: Commit**

```powershell
git add .github/workflows/android-apk.yml test/app/platform_configuration_test.dart
git commit -m "ci: publish signed updates through R2"
```

### Task 10: Update Local Release Build Script

**Files:**
- Modify: `tool/build_versioned_apk.ps1`
- Create: `test/app/build_versioned_apk_script_test.dart`

**Interfaces:**
- Consumes: signed feed and permanent Android signing environment.
- Produces: locally built `BibleRecite-{version}+{build}.apk` with an explicitly safe build.

- [ ] **Step 1: Write script-content regression tests**

Assert the script accepts `-BuildNumber`, refuses an offline automatic build without it, passes `--build-number`, and verifies the output certificate with `apksigner` before printing the path.

- [ ] **Step 2: Implement safe build selection**

Add parameters:

```powershell
param(
    [switch]$SkipVersionBump,
    [int]$BuildNumber = 0,
    [switch]$Offline
)
```

When online and no explicit build is supplied, fetch/verify the signed feed through the Dart resolver and select a higher build. When offline and `BuildNumber -le 0`, throw. Continue using the permanent local keystore and reject a certificate mismatch.

- [ ] **Step 3: Run test and one local version-preserving build**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test test\app\build_versioned_apk_script_test.dart
powershell -ExecutionPolicy Bypass -File tool\build_versioned_apk.ps1 -SkipVersionBump -BuildNumber 7 -Offline
```

Expected: test PASS; APK builds and fixed SHA-256 certificate is printed.

- [ ] **Step 4: Commit**

```powershell
git add tool/build_versioned_apk.ps1 test/app/build_versioned_apk_script_test.dart
git commit -m "build: keep local update versions monotonic"
```

### Task 11: Configure Cloudflare Secrets and End-to-End Verification

**Files:**
- Modify only if verification exposes defects in files owned by Tasks 1–10.

**Interfaces:**
- Consumes: Cloudflare R2 bucket/custom domain/API token, update key, GitHub CLI, connected Android device.
- Produces: a real signed update feed and successful old-to-new phone upgrade.

- [ ] **Step 1: Create R2 with minimum permissions**

Create one Standard R2 bucket, attach the approved custom download domain, create an object read/write token scoped only to that bucket, and record the public base URL. Do not enable public write access.

- [ ] **Step 2: Generate and store update signing material**

Confirm the Task 2 public key matches the private `UPDATE_MANIFEST_PRIVATE_KEY` secret by signing and verifying a disposable payload. Set `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, and `R2_PUBLIC_BASE_URL` with `gh secret set`, ensuring values never appear in logs.

- [ ] **Step 3: Run complete local verification**

Run:

```powershell
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat test
D:\gitcode\bible_recite\.toolchains\flutter\bin\flutter.bat analyze
git diff --check
```

Expected: all tests PASS, analyze says `No issues found!`, diff check is clean.

- [ ] **Step 4: Push and watch the cloud workflow**

Push the implementation branch, run/watch `Mobile releases`, and require Android, iOS, Release, R2 upload and signed-feed steps all succeed. Inspect Release assets and download the R2 APK independently.

- [ ] **Step 5: Independently verify cloud outputs**

Check GitHub/R2 SHA-256 equality, verify signed envelope using the committed public key, and run `apksigner verify --verbose --print-certs`. Expected certificate ends in `39b5a7e7` and v2 verifies true.

- [ ] **Step 6: Verify real-phone update and fallbacks**

Install the preceding APK, open About, confirm new version/build, download over R2, grant unknown-source permission, install over the old app, and verify SQLite plans/statistics remain. Repeat with R2 URL deliberately made unreachable in a test manifest and confirm GitHub fallback. Confirm cellular confirmation and cancel/resume behavior.

- [ ] **Step 7: Final commit for verification-only corrections**

If corrections were required, run focused and full tests again and stage only update-owned paths:

```powershell
git add lib/src/features/update lib/src/features/statistics/presentation/statistics_screen.dart lib/src/features/plans/data/sqlite_plan_repository.dart android/app/src/main .github/workflows/android-apk.yml tool/update_feed tool/build_versioned_apk.ps1 test/update test/statistics test/app
git commit -m "fix: complete secure update verification"
```

If no correction was required, do not create an empty commit.

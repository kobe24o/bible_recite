# Cross-Platform Packaging and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce reproducible, verified Android, iOS, Windows, and macOS release artifacts that contain the complete scripture and speech assets, work without network access, and pass platform, accessibility, licensing, notification, backup, and long-session acceptance gates.

**Architecture:** One reusable `prepare-release-inputs` job turns pinned URLs, licenses, sizes, and SHA-256 values into a single immutable model/input artifact and exposes its artifact digest. Every platform workflow consumes and re-verifies that same artifact, then inspects its packaged output instead of trusting the build exit code. Unsigned Apple builds and CI-test-signed packages are compile/installation gates only; user-distributable signatures run in protected environments with owner credentials. Acceptance tests exercise installed apps, real plugins, external restart/permission controls, and package identity.

**Tech Stack:** Flutter 3.44.4, Dart 3.12.2, GitHub Actions, Android Gradle/JDK 17, Android bundletool/apksigner, Xcode 26 toolchain, codesign/notarytool, MSIX Packaging Toolchain, signtool, PowerShell, Flutter integration_test.

## Global Constraints

- Execute this plan after the foundation, offline recitation, and local-data plans.
- Release artifacts contain the three verified scripture packs, SenseVoice INT8, Silero VAD, notices, and licenses; no runtime download is allowed.
- Android, iOS, macOS, and Windows configurations must not declare unnecessary network permissions/capabilities. On iOS and full-trust Windows this does not itself block sockets, so offline proof also requires dependency scanning and firewall/physical-disconnection evidence.
- Pin Flutter, Dart packages, source archives, model archives, and the lockfile. Never download a `latest` asset.
- Public CI must not contain private audio, signing certificates, passwords, API tokens, or store credentials.
- Apple signed artifacts need a user-owned Apple Developer identity and notarization/App Store credentials. Windows self-hosted MSIX needs a trusted PFX or Store signing. Their absence blocks signed distribution, not source/build completion.
- The authoritative version is `pubspec.yaml` (`1.0.0+1` initially). A release tag must equal `v` plus the build name; every platform receives the same explicit build name and build number.
- “Reproducible” means traceable source commit, toolchain, input hashes, unsigned payload hash, signer, and signed artifact hash. Timestamped signatures/notarization are not expected to be byte-identical across runs.
- Every task starts with a failing verification, ends with the focused and full checks, and has one intentional commit.

---

## File Structure

```text
assets/licenses/THIRD_PARTY_NOTICES.txt
assets/models/manifests/release-assets.json
docs/release/platform-acceptance.md
docs/release/signing.md
docs/release/third-party-licenses.md
tool/release/build_release_manifest.dart
tool/release/verify_artifact.dart
tool/release/verify_android_permissions.dart
tool/release/verify_apple_entitlements.dart
tool/release/verify_windows_manifest.dart
tool/release/verify_licenses.dart
tool/release/prepare_release_inputs.dart
tool/release/configure_windows_msix.dart
tool/release/windows_msix_profiles.json
tool/release/android-arm64-device.json
tool/release/android-x86_64-device.json
tool/acceptance/audio_quality_gate.dart
tool/acceptance/validate_audio_dataset.dart
tool/acceptance/windows_packaged_smoke.ps1
test/release/*.dart
test/accessibility/*.dart
integration_test/release_smoke_test.dart
integration_test/offline_smoke_test.dart
integration_test/notification_smoke_test.dart
integration_test/backup_round_trip_test.dart
integration_test/keyboard_navigation_test.dart
integration_test/asr_acceptance_test.dart
integration_test/long_session_test.dart
.github/workflows/quality.yml
.github/workflows/prepare-release-inputs.yml
.github/workflows/build-android.yml
.github/workflows/build-ios.yml
.github/workflows/build-macos.yml
.github/workflows/build-windows.yml
.github/workflows/release.yml
android/app/src/main/AndroidManifest.xml
android/app/build.gradle.kts
android/settings.gradle.kts
android/app/src/main/res/drawable/ic_notification.xml
android/app/src/main/res/raw/keep.xml
ios/Runner/Info.plist
ios/Runner/Runner.entitlements
ios/Runner/AppDelegate.swift
ios/Runner/BackupDocumentPlugin.swift
ios/RunnerUITests/AccessibilityTests.swift
macos/Runner/DebugProfile.entitlements
macos/Runner/Release.entitlements
macos/DeveloperIDExportOptions.example.plist
windows/runner/Runner.rc
windows/runner/resources/app_icon.ico
```

## Task 1: Make bundled assets and license provenance release-verifiable

**Files:**
- Create: `assets/models/manifests/release-assets.json`
- Create: `assets/licenses/THIRD_PARTY_NOTICES.txt`
- Create: `docs/release/third-party-licenses.md`
- Create: `tool/release/verify_licenses.dart`
- Create: `tool/release/verify_artifact.dart`
- Create: `tool/release/prepare_release_inputs.dart`
- Modify: `lib/src/features/scripture/presentation/scripture_sources_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_en.arb`
- Create: `test/release/release_assets_test.dart`
- Create: `test/release/in_app_licenses_test.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: a single release asset catalog and `verify_licenses.dart` gate.
- Consumes: scripture pack manifests and speech asset manifests produced by earlier plans.

- [ ] **Step 1: Write a failing manifest and license test**

```dart
test('every bundled binary has a concrete hash and license', () async {
  final catalog = await ReleaseAssetCatalog.load(
    File('assets/models/manifests/release-assets.json'),
  );
  expect(catalog.assets, isNotEmpty);
  for (final asset in catalog.assets) {
    expect(asset.sourceSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(asset.sourceSizeBytes, greaterThan(0));
    expect(asset.sourceUrl.scheme, anyOf('https', 'file'));
    expect(asset.licenses, isNotEmpty);
    for (final license in asset.licenses) {
      expect(license.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(license.sourceUrl.path, isNot(contains('/latest')));
      expect(license.attribution.trim(), isNotEmpty);
    }
  }
});
```

- [ ] **Step 2: Run and confirm the catalog is missing**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/release/release_assets_test.dart`

Expected: FAIL because `ReleaseAssetCatalog` and the catalog do not exist.

- [ ] **Step 3: Add the concrete release asset catalog**

Include these already verified upstream archives:

```json
{
  "schemaVersion": 1,
  "assets": [
    {
      "id": "sensevoice-int8-2024-07-17",
      "sourceUrl": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2",
      "sourceSha256": "7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e",
      "sourceSizeBytes": 163002883,
      "licenses": [
        {"sourceUrl":"https://raw.githubusercontent.com/FunAudioLLM/SenseVoice/35a9b45369f72f79083f1d98ee78175f0ea53eed/LICENSE","sha256":"221c6df10b0931a5629adad671ea48fb7747e034c414b6d2bfa275bc3dd4ea17","destination":"assets/licenses/SenseVoice-LICENSE-pointer.txt","attribution":"SenseVoiceSmall by FunAudioLLM; retain the SenseVoiceSmall model name"},
        {"sourceUrl":"https://raw.githubusercontent.com/modelscope/FunASR/b1a7283d97b61ddeef25d13f3b56b62a896ee3bb/MODEL_LICENSE","sha256":"7dba975a2069691db4992b0592d70828b330d2f8a30a71450f4e152a554e84f8","destination":"assets/licenses/FunASR-MODEL_LICENSE-1.1.txt","attribution":"FunASR Model Open Source License Agreement 1.1; Alibaba Group attribution and model name retained"}
      ]
    },
    {
      "id": "silero-vad",
      "sourceUrl": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx",
      "sourceSha256": "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6",
      "sourceSizeBytes": 643854,
      "licenses": [
        {"sourceUrl":"https://raw.githubusercontent.com/snakers4/silero-vad/b163605b3f44c3aadf28f97b125a2f7c461e9a7f/LICENSE","sha256":"2e63e9a38b6e8fc0c7bc37ce174caca1862870856c6daf5697cfb785e925520b","destination":"assets/licenses/Silero-VAD-MIT.txt","attribution":"Silero VAD by Silero Team, MIT License"}
      ]
    }
  ]
}
```

`prepare_release_inputs.dart` calls the earlier `tool/models/bin/prepare_models.dart`, fetches each pinned license, and adds `bundledFiles[{path,sizeBytes,sha256}]` for every extracted model/token/license to `build/release-inputs/release-assets.generated.json`. It also inventories sherpa-onnx, ONNX Runtime, Flutter plugins, and bundled native libraries from `pubspec.lock`/the resolved package cache and emits their full notices. Register the catalog, notices, and full license files as Flutter assets. Extend the existing offline source screen with “识别模型与第三方组件” sections showing model/library name, pinned source as copyable text, version/hash, attribution, and complete bundled terms; it must not fetch or open a URL. Add matching Simplified Chinese, Traditional Chinese, and English ARB keys and a widget test proving all bundled licenses are reachable offline. `verify_licenses.dart` rejects license pointers without their referenced full terms, missing model-name attribution, absent/empty notices, wrong hashes, unlisted native libraries, and `/latest` URLs. Legal review of the FunASR Model License is a release gate, not an assumption that it is equivalent to an OSI license. `verify_artifact.dart` opens a platform artifact or unpacked app, streams every registered asset, and compares final byte size/hash against the generated catalog.

- [ ] **Step 4: Verify generated assets and notices**

```powershell
.\.toolchains\flutter\bin\dart.bat run tool/release/prepare_release_inputs.dart --output build/release-inputs
.\.toolchains\flutter\bin\dart.bat run tool/release/verify_licenses.dart --catalog build/release-inputs/release-assets.generated.json
.\.toolchains\flutter\bin\flutter.bat test test/release/release_assets_test.dart
```

Expected: all hashes match, every asset has a license, and the test passes.

- [ ] **Step 5: Commit**

```powershell
git add assets/models/manifests assets/licenses docs/release/third-party-licenses.md lib/src/features/scripture/presentation/scripture_sources_screen.dart lib/l10n tool/release/prepare_release_inputs.dart tool/release/verify_licenses.dart tool/release/verify_artifact.dart test/release pubspec.yaml pubspec.lock
git commit -m "build: verify bundled assets and licenses"
```

## Task 2: Establish deterministic public quality CI

**Files:**
- Create: `.github/workflows/quality.yml`
- Create: `.github/workflows/prepare-release-inputs.yml`
- Create: `tool/release/verify_generated_files.dart`
- Create: `test/release/no_network_dependency_test.dart`
- Modify: `analysis_options.yaml`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: reusable quality and immutable release-input workflows for all platform builds.
- Consumes: the pinned Flutter bootstrap and committed `pubspec.lock`.

- [ ] **Step 1: Add tests that fail on accidental runtime networking**

Scan `lib/` and platform manifests for forbidden HTTP clients, `INTERNET`, network client/server entitlements, and unapproved URL schemes. Permit URLs only in `tool/`, source manifests, provenance screens, and documentation.

- [ ] **Step 2: Run locally and confirm the missing verifier failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/release/no_network_dependency_test.dart`

Expected: FAIL because the verifier does not exist.

- [ ] **Step 3: Add the quality workflow**

Add Flutter's integration-test SDK package once:

```powershell
.\.toolchains\flutter\bin\flutter.bat pub add "dev:integration_test:{sdk: flutter}"
```

Both workflows expose `on: workflow_call`. Pin actions by full commit: `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5`, `subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2`, `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02`, and `actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093`. Record those SHAs in Dependabot/security review rather than using movable major tags.

The quality workflow installs Flutter `3.44.4`, restores no generated model assets, and runs:

```powershell
dart format --output=none --set-exit-if-changed .
dart run build_runner build --delete-conflicting-outputs
git diff --exit-code
dart run tool/release/verify_generated_files.dart
flutter analyze --fatal-infos --fatal-warnings
flutter test --exclude-tags model
dart run tool/release/verify_licenses.dart --catalog assets/models/manifests/release-assets.json --metadata-only
```

The workflow must use dependency caching keyed by `pubspec.lock` and cancel superseded pull-request runs.

`prepare-release-inputs.yml` runs after quality in a clean checkout, executes:

```powershell
dart run tool/release/prepare_release_inputs.dart --output build/release-inputs
dart run tool/release/verify_licenses.dart --catalog build/release-inputs/release-assets.generated.json
flutter test --tags model test/recitation/sensevoice_fixture_test.dart
```

It uploads the whole `build/release-inputs` directory once as artifact `release-inputs-${{ github.sha }}` and exposes both the artifact name and `upload-artifact`'s `artifact-digest` as reusable-workflow outputs. Platform jobs download by that exact name in the same caller run, compare the reported digest, copy the verified runtime assets into the Flutter asset path, and rerun the generated catalog verifier. They never independently download the model.

- [ ] **Step 4: Run the same gate locally**

Expected: formatting produces no diff, generated files are current, analysis has zero issues, and all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add .github/workflows/quality.yml .github/workflows/prepare-release-inputs.yml analysis_options.yaml pubspec.yaml pubspec.lock tool/release/verify_generated_files.dart test/release/no_network_dependency_test.dart
git commit -m "ci: add deterministic quality gates"
```

## Task 3: Package and inspect Android APK and AAB artifacts

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/settings.gradle.kts`
- Create: `android/app/src/main/res/drawable/ic_notification.xml`
- Create: `android/app/src/main/res/raw/keep.xml`
- Create: `android/app/src/main/res/xml/backup_rules.xml`
- Create: `android/app/src/main/res/xml/data_extraction_rules.xml`
- Create: `tool/release/verify_android_permissions.dart`
- Create: `tool/release/android-arm64-device.json`
- Create: `tool/release/android-x86_64-device.json`
- Create: `test/release/android_manifest_test.dart`
- Create: `.github/workflows/build-android.yml`

**Interfaces:**
- Produces: release APK, AAB, checksums, and inspection JSON.
- Consumes: all generated scripture/model assets and the quality workflow.

- [ ] **Step 1: Write a failing Android manifest policy test**

Assert microphone, Android 13 notification, and `RECEIVE_BOOT_COMPLETED` permissions are present; `android.permission.INTERNET`, exact-alarm permission, and cleartext traffic are absent. Require `android:allowBackup="false"` plus backup/data-extraction rules that exclude database, recordings, models, and restore state. Assert `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`, notification icon resources, and `res/raw/keep.xml` are present.

- [ ] **Step 2: Run and confirm policy failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/release/android_manifest_test.dart`

Expected: FAIL until the manifest and verifier match the policy.

- [ ] **Step 3: Configure the release build**

Pin compileSdk/targetSdk 36 and minSdk 24. Keep the Flutter 3.44.4 template's mutually compatible Gradle 9.1.0, AGP 9.0.1, and Kotlin 2.3.20 rather than partially downgrading the toolchain; use JDK 17 and add only core-library desugaring with `desugar_jdk_libs:2.1.4` plus `multiDexEnabled true`, matching `flutter_local_notifications 22.0.1`. Use release shrinking only after keep-rule tests pass, ABI splits for APK distribution, and an AAB for Play. `verify_android_permissions.dart` uses `apkanalyzer`/`aapt2` on final artifacts and inspects every ABI's sherpa/ONNX libraries, not only source XML.

Define two signing classes. `ci-test-signed` uses an ephemeral certificate solely for runner installation and is never publishable. `production-upload-signed` runs in a protected environment, materializes signing config from secrets, deletes it afterward, and requires a nonempty protected `ANDROID_UPLOAD_CERT_SHA256` environment value. Normalize it to lowercase hex and compare it byte-for-byte with `apksigner --print-certs` output for every APK and the certificate extracted from the AAB; a missing or mismatched value blocks user distribution. A Flutter template debug signature must never qualify.

- [ ] **Step 4: Build and verify both forms**

```powershell
.\.toolchains\flutter\bin\flutter.bat build apk --release --split-per-abi --build-name 1.0.0 --build-number 1
.\.toolchains\flutter\bin\flutter.bat build appbundle --release --build-name 1.0.0 --build-number 1
Get-ChildItem build\app\outputs\flutter-apk\*-release.apk | ForEach-Object { .\.toolchains\flutter\bin\dart.bat run tool/release/verify_artifact.dart --platform android --artifact $_.FullName --catalog build/release-inputs/release-assets.generated.json; .\.toolchains\flutter\bin\dart.bat run tool/release/verify_android_permissions.dart --apk $_.FullName; & "$env:ANDROID_SDK_ROOT\build-tools\35.0.0\apksigner.bat" verify --verbose --print-certs $_.FullName }
jarsigner -verify -strict -verbose -certs build/app/outputs/bundle/release/app-release.aab
java -jar build/tooling/bundletool-1.18.3.jar validate --bundle build/app/outputs/bundle/release/app-release.aab
java -jar build/tooling/bundletool-1.18.3.jar build-apks --bundle build/app/outputs/bundle/release/app-release.aab --output build/app/outputs/bundle/release/arm64-device.apks --device-spec tool/release/android-arm64-device.json
java -jar build/tooling/bundletool-1.18.3.jar build-apks --bundle build/app/outputs/bundle/release/app-release.aab --output build/app/outputs/bundle/release/x86_64-device.apks --device-spec tool/release/android-x86_64-device.json
```

The workflow downloads/re-verifies the one release-input artifact before these commands and installs Android build-tools 35.0.0 plus pinned bundletool 1.18.3. Run AAB-generated `.apks` on an arm64 device spec and an x86_64 emulator spec; verify launch, model load, and matching native ABI libraries. Record APK/AAB certificate fingerprints and require the approved production fingerprint for publishable artifacts. Expected: all split APKs and the AAB contain identical packs/models; no INTERNET permission; signatures are strict-valid. Treat the current 500 MB base-module limit as a hard gate and the 200 MB large-app warning as a product review gate, per [Google Play app size limits](https://support.google.com/googleplay/android-developer/answer/9859372?hl=en).

- [ ] **Step 5: Commit**

```powershell
git add android tool/release/verify_android_permissions.dart test/release/android_manifest_test.dart .github/workflows/build-android.yml
git commit -m "ci(android): build and inspect release artifacts"
```

## Task 4: Add iOS unsigned CI and the signed IPA release path

**Files:**
- Modify: `ios/Runner/Info.plist`
- Modify: `ios/Runner/Runner.entitlements`
- Modify: `ios/Runner/AppDelegate.swift`
- Modify: `ios/Runner/BackupDocumentPlugin.swift`
- Create: `ios/Runner/en.lproj/InfoPlist.strings`
- Create: `ios/Runner/zh-Hans.lproj/InfoPlist.strings`
- Create: `ios/Runner/zh-Hant.lproj/InfoPlist.strings`
- Create: `ios/ExportOptions.example.plist`
- Create: `ios/RunnerTests/BackupDocumentPluginTests.swift`
- Create: `tool/release/verify_apple_entitlements.dart`
- Create: `test/release/ios_configuration_test.dart`
- Create: `.github/workflows/build-ios.yml`
- Create: `docs/release/signing.md`

**Interfaces:**
- Produces: unsigned Runner.app compile artifact and documented signed IPA gate.
- Consumes: macOS runner and owner-provided Apple credentials only for signed releases.

- [ ] **Step 1: Write a failing iOS configuration test**

Require iOS 13, localized `NSMicrophoneUsageDescription` strings in English, Simplified Chinese, and Traditional Chinese, `UNUserNotificationCenter` delegate setup in AppDelegate, document-picker backup round trips, and `NSURLIsExcludedFromBackupKey` on the private database, recording blobs, copied model directory, and restore state. Explicitly reject Push Notifications capability and `aps-environment`: local notifications do not require APNs. Add document type/export declarations only if the app registers its `.brbkp` type; ordinary document pickers do not need public Documents access. Reject committed profiles, certificates, passwords, or filled ExportOptions files.

- [ ] **Step 2: Run and confirm failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/release/ios_configuration_test.dart`

Expected: FAIL until configuration is explicit.

- [ ] **Step 3: Implement native notification and backup-exclusion policy**

In `AppDelegate.swift`, set `UNUserNotificationCenter.current().delegate` during launch and register the existing `BackupDocumentPlugin`. Extend that plugin with an idempotent method that sets `URLResourceKey.isExcludedFromBackupKey` and verifies the value. Call it whenever the user database, a recording blob, the copied/versioned model directory, or restore state is created, imported, installed, or recovered at startup. A failure is surfaced and blocks the operation; it is not logged and ignored. `BackupDocumentPluginTests.swift` creates private fixtures and proves the resource value survives reopening, and the configuration test proves each creation/restore call site invokes the policy.

- [ ] **Step 4: Add unsigned and signed workflow branches**

Public CI runs:

```bash
flutter build ios --release --no-codesign --build-name 1.0.0 --build-number 1
dart run tool/release/verify_artifact.dart --platform ios --artifact build/ios/iphoneos/Runner.app --catalog build/release-inputs/release-assets.generated.json
```

The protected release environment imports the owner's certificate/profile and runs:

```bash
flutter build ipa --release --build-name 1.0.0 --build-number 1 --export-options-plist=ios/ExportOptions.plist
codesign --verify --deep --strict --verbose=2 build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
codesign -d --entitlements :- build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
```

The workflow consumes the common release-input artifact. Document that unsigned CI proves compilation and source/build settings only; effective entitlements are accepted from the final signed IPA. Device installation and App Store/TestFlight acceptance require signing, as described by the [Flutter iOS release guide](https://docs.flutter.dev/deployment/ios).

- [ ] **Step 5: Run native/configuration tests and an unsigned build on macOS**

Expected: Swift plugin tests and Dart configuration tests pass, Runner.app is built, models and packs are present, no APNs entitlement is requested, and every private user/model file class is excluded from iCloud/device backup. Absence of an iOS network entitlement is recorded only as “no unnecessary capability,” not proof sockets are impossible; controlled firewall/connection logging supplies offline evidence.

- [ ] **Step 6: Commit**

```powershell
git add ios tool/release/verify_apple_entitlements.dart test/release/ios_configuration_test.dart .github/workflows/build-ios.yml docs/release/signing.md
git commit -m "ci(ios): add unsigned build and signed ipa path"
```

## Task 5: Build separate macOS arm64 and x64 signed artifacts

**Files:**
- Modify: `macos/Runner/DebugProfile.entitlements`
- Modify: `macos/Runner/Release.entitlements`
- Modify: `macos/Runner/Info.plist`
- Create: `macos/Runner/en.lproj/InfoPlist.strings`
- Create: `macos/Runner/zh-Hans.lproj/InfoPlist.strings`
- Create: `macos/Runner/zh-Hant.lproj/InfoPlist.strings`
- Create: `macos/DeveloperIDExportOptions.example.plist`
- Create: `test/release/macos_configuration_test.dart`
- Create: `.github/workflows/build-macos.yml`

**Interfaces:**
- Produces: separate arm64 and x64 app archives; optional signed/notarized releases.
- Consumes: `verify_apple_entitlements.dart` and owner-provided Developer ID credentials.

- [ ] **Step 1: Write a failing sandbox/architecture test**

Require App Sandbox, audio-input, user-selected-file read/write, hardened runtime for Developer ID distribution, and localized `NSMicrophoneUsageDescription` strings in English, Simplified Chinese, and Traditional Chinese. Reject network client/server entitlements. Require explicit `macos-26` arm64 and `macos-26-intel` x64 jobs; prevent a universal merge unless every bundled framework/dylib/bundle is proven universal. The verifier rejects Flutter's CI-generated temporary entitlement that disables App Sandbox and inspects the final `.app/Contents/Info.plist` for the microphone key.

- [ ] **Step 2: Run and confirm failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/release/macos_configuration_test.dart`

Expected: FAIL until entitlements and workflow matrix exist.

- [ ] **Step 3: Build and inspect both architectures**

Each runner consumes the common release-input artifact. Do not rely on `flutter build macos --release` selecting the runner architecture: Flutter 3.44.4 uses a generic destination and normally produces a universal build. Run configuration generation once, then build explicitly:

```bash
flutter build macos --release --config-only --build-name 1.0.0 --build-number 1
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release -derivedDataPath build/macos-arm64 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release -derivedDataPath build/macos-x64 ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
```

Run only the matching command on each runner. Inspect the app executable, Flutter framework, every dylib, and every plugin bundle with `lipo -info`; any wrong/mixed architecture fails. Because ordinary Flutter CI can disable App Sandbox in a temporary entitlement, release acceptance must use the direct Xcode path and the checked-in `Release.entitlements`.

Maintain separate protected channels for Mac App Store signing and Developer ID distribution. Commit only `DeveloperIDExportOptions.example.plist`; the protected job materializes `macos/DeveloperIDExportOptions.plist` with method `developer-id` and owner-controlled signing identity, then deletes it. On the matching architecture runner, create and export a genuinely signed archive before any verification (`$arch` is exactly `arm64` or `x86_64`):

```bash
arch="${MATRIX_ARCH:?MATRIX_ARCH must be arm64 or x86_64}"
case "$arch" in arm64|x86_64) ;; *) exit 2 ;; esac
archive="build/macos-archives/bible_recite-${arch}.xcarchive"
export_dir="build/macos-signed/${arch}"
app="${export_dir}/bible_recite.app"
xcodebuild archive -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release -archivePath "$archive" ARCHS="$arch" ONLY_ACTIVE_ARCH=YES
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" -exportOptionsPlist macos/DeveloperIDExportOptions.plist
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements :- "$app"
plutil -extract NSMicrophoneUsageDescription raw "$app/Contents/Info.plist"
ditto -c -k --sequesterRsrc --keepParent "$app" "build/releases/macos/bible_recite-${arch}-notarization.zip"
xcrun notarytool submit "build/releases/macos/bible_recite-${arch}-notarization.zip" --keychain-profile bible-recite-notary --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "build/releases/macos/bible_recite-${arch}.zip"
```

Run the full sequence once for `arm64` and once for `x86_64`; record distinct unsigned payload, exported app, notarization ZIP, and final ZIP hashes. An interactive release runner also runs `tccutil reset Microphone <bundle-id>` before separate allow and deny launches, verifying recording succeeds only after allow and the localized recovery UI appears after deny.

Follow the [Flutter macOS deployment guidance](https://docs.flutter.dev/deployment/macos) for entitlements, signing, and distribution.

- [ ] **Step 4: Run tests and unsigned architecture builds**

Expected: both single-architecture app archives contain matching scripture/model hashes and launch. The final signed app exposes App Sandbox, audio input, user-selected file access, no unnecessary network entitlement, valid Developer ID signature, stapled notarization, and Gatekeeper acceptance. Mac App Store artifacts use their own distribution/profile path and are never passed through the Developer ID script. Signed/notarized checks run only when credentials are installed; otherwise the distribution channel is blocked, not downgraded.

- [ ] **Step 5: Commit**

```powershell
git add macos test/release/macos_configuration_test.dart .github/workflows/build-macos.yml
git commit -m "ci(macos): build separate desktop architectures"
```

## Task 6: Package Windows x64 as an identity-bearing MSIX

**Files:**
- Modify: `windows/runner/Runner.rc`
- Modify: `pubspec.yaml`
- Modify: `lib/src/features/reminders/data/flutter_local_notifications_gateway.dart`
- Create: `tool/release/configure_windows_msix.dart`
- Create: `tool/release/windows_msix_profiles.json`
- Create: `tool/release/verify_windows_manifest.dart`
- Create: `tool/acceptance/windows_packaged_smoke.ps1`
- Create: `test/release/windows_manifest_test.dart`
- Create: `.github/workflows/build-windows.yml`

**Interfaces:**
- Produces: portable x64 ZIP and identity-bearing MSIX; the MSIX is authoritative for Windows notification acceptance.
- Consumes: `msix` package configuration and optional user-owned signing certificate.

- [ ] **Step 1: Write a failing package identity test**

Test three explicit profiles: CI identity `BibleRecite.Test`, a protected self-hosted sideload identity/publisher matching its certificate subject, and the exact Partner Center identity with `store:true`. Require x64, microphone/file-picker behavior, LocalAppData rather than RoamingState, and toast activator CLSID `0B2FC8E1-91F3-4B37-9D09-66F1C29C5E9A` in both the final manifest and `WindowsInitializationSettings.guid`. Reject unnecessary internet client/server capabilities, while documenting that a full-trust Win32 app can still open sockets.

- [ ] **Step 2: Run and confirm failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/release/windows_manifest_test.dart`

Expected: FAIL because the manifest/verifier are missing.

- [ ] **Step 3: Add portable and packaged workflows**

Add `msix:3.18.0` as a development dependency. Configure display name `圣经背诵`, executable `bible_recite.exe`, x64, icon, `build_windows:false`, deterministic output path/name, the fixed toast CLSID, `sign_msix:false`, and `install_certificate:false`. Do not maintain a hand-written manifest that `msix:create` ignores. Run `msix:build`, let `configure_windows_msix.dart` edit and validate the generated `AppxManifest.xml` for one named profile, then run `msix:pack` without rebuilding Windows. Every CI/self-hosted signature is applied explicitly afterward; the Store profile remains unsigned for Partner Center signing and never inherits CI certificate settings.

`windows_msix_profiles.json` contains only the CI test identity/publisher and profile schema. Partner Center identity/publisher and self-hosted certificate subject come from protected environment configuration and are compared exactly. The CI profile creates a temporary PFX for `CN=BibleRecite CI Test`, installs its certificate only in the isolated runner's TrustedPeople store, and removes package/certificate after the test. CI-test-signed output is never published.

```powershell
.\.toolchains\flutter\bin\flutter.bat build windows --release --build-name 1.0.0 --build-number 1
.\.toolchains\flutter\bin\dart.bat run msix:build
.\.toolchains\flutter\bin\dart.bat run tool/release/configure_windows_msix.dart --profile ci-test --version 1.0.0.0
.\.toolchains\flutter\bin\dart.bat run msix:pack
$msix = (Get-ChildItem build\windows -Recurse -Filter '*.msix' | Select-Object -First 1).FullName
if (!(Test-Path -LiteralPath $pfx) -or [string]::IsNullOrWhiteSpace($env:CI_PFX_PASSWORD)) { throw "Explicit CI signing PFX/password missing" }
$publisher = (.\.toolchains\flutter\bin\dart.bat run tool/release/verify_windows_manifest.dart --msix $msix --print-publisher).Trim()
$securePassword = ConvertTo-SecureString $env:CI_PFX_PASSWORD -AsPlainText -Force
$pfxData = Get-PfxData -FilePath $pfx -Password $securePassword
$pfxSubject = $pfxData.EndEntityCertificates[0].Subject
if ($pfxSubject -cne $publisher) { throw "PFX subject does not equal manifest Publisher" }
signtool sign /fd SHA256 /f $pfx /p $env:CI_PFX_PASSWORD $msix
signtool verify /pa /all /v $msix
$identity = .\.toolchains\flutter\bin\dart.bat run tool/release/verify_windows_manifest.dart --msix $msix --print-identity
Add-AppxPackage -Path $msix
Get-AppxPackage -Name $identity
powershell -File tool\acceptance\windows_packaged_smoke.ps1 -PackageName $identity
```

The workflow consumes/re-verifies the common release-input artifact before building. A self-hosted release checks certificate Subject equals final manifest Publisher and records its SHA-256 fingerprint. A Store upload uses the Partner Center identity and Store signing; it is not the CI identity. Notification query/cancellation is accepted only in packaged MSIX context because Windows package identity is required; see the [Flutter Windows deployment guide](https://docs.flutter.dev/deployment/windows).

- [ ] **Step 4: Verify install, launch, toast, cancel, and uninstall**

Expected: installed package launches from Start, toast activation routes to `/today`, cancellation works after restart, and the smoke script removes its test package/data.

- [ ] **Step 5: Commit**

```powershell
git add windows pubspec.yaml pubspec.lock lib/src/features/reminders/data/flutter_local_notifications_gateway.dart tool/release/configure_windows_msix.dart tool/release/windows_msix_profiles.json tool/release/verify_windows_manifest.dart tool/acceptance/windows_packaged_smoke.ps1 test/release/windows_manifest_test.dart .github/workflows/build-windows.yml
git commit -m "ci(windows): package and verify identity-bearing msix"
```

## Task 7: Exercise notification and encrypted-backup plugins on all four platforms

**Files:**
- Create: `integration_test/notification_smoke_test.dart`
- Create: `integration_test/backup_round_trip_test.dart`
- Create: `test/release/platform_acceptance_contract_test.dart`
- Create: `docs/release/platform-acceptance.md`

**Interfaces:**
- Produces: platform evidence for real plugin behavior.
- Consumes: reminder and backup implementations from the local-data plan.

- [ ] **Step 1: Write failing plugin acceptance scenarios**

Notifications cover permission granted, denied, one-shot scheduling, pending-list query, force-stop/process restart, activation route, and cancellation. Backups cover export, import, picker cancellation, wrong password/corrupted tag, process-death recovery, and a generated 256 MiB recording-inclusive backup without loading the complete file into Dart heap. Privacy checks assert Android system backup is disabled/excluded, iOS marks private user files excluded from backup, and Windows stores data in LocalAppData rather than RoamingState.

- [ ] **Step 2: Run on one configured device and confirm missing harness failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test integration_test/notification_smoke_test.dart -d windows`

Expected: FAIL because the integration harness is missing.

- [ ] **Step 3: Implement deterministic test hooks**

Use dependency-injected clock/notification IDs and a release-disabled diagnostic route. Never bypass the platform plugin. A single Flutter integration process cannot prove permission reset or post-restart activation: Android's outer script uses `pm grant/revoke`, `am force-stop`, relaunch, and notification taps; iOS uses `simctl` plus XCTest; macOS and packaged Windows use external launch/terminate/activate scripts on interactive self-hosted runners. Schedule at most 32 rolling one-shot notifications so the same behavior fits iOS's 64 pending limit and Windows's no-repeat constraint.

- [ ] **Step 4: Run the four-platform matrix**

```powershell
.\.toolchains\flutter\bin\flutter.bat test integration_test/notification_smoke_test.dart -d emulator-5554
.\.toolchains\flutter\bin\flutter.bat test integration_test/backup_round_trip_test.dart -d emulator-5554
```

On a macOS runner run the macOS app under the external process harness and the iOS XCTest suite against the concrete simulator UDID. On Windows use the packaged smoke script, not loose-runner notification results. Ordinary hosted/headless runners may verify API calls and pending state, but presentation/click activation evidence requires an interactive self-hosted/lab runner.

Expected: every scenario passes and writes a timestamped JSON evidence record with platform, OS, app version, artifact hash, and test result.

- [ ] **Step 5: Commit**

```powershell
git add integration_test/notification_smoke_test.dart integration_test/backup_round_trip_test.dart test/release/platform_acceptance_contract_test.dart docs/release/platform-acceptance.md
git commit -m "test(platform): verify notifications and backups"
```

## Task 8: Enforce offline ASR quality and long-session performance gates

**Files:**
- Create: `tool/acceptance/validate_audio_dataset.dart`
- Create: `tool/acceptance/audio_quality_gate.dart`
- Create: `tool/acceptance/assert_android_no_default_network.ps1`
- Create: `integration_test/offline_smoke_test.dart`
- Create: `integration_test/asr_acceptance_test.dart`
- Create: `integration_test/long_session_test.dart`
- Create: `docs/testing/private-audio-manifest.schema.json`

**Interfaces:**
- Produces: machine-readable quality/performance report and release-blocking thresholds.
- Consumes: private licensed audio mounted at `AUDIO_ACCEPTANCE_ROOT`; no private audio enters Git.

- [ ] **Step 1: Write failing dataset and metric tests**

Require each language to have at least 8 speakers, 150 fully correct samples, and 75 deliberate-error samples. Require speaker-disjoint tuning and acceptance splits and verify every audio SHA-256. Calculate the false-fail and omission false-pass thresholds independently for Mandarin and English, never only as an aggregate. Add metric tests for model cold start, real-time factor, dropped segment sequence, and RSS trend.

- [ ] **Step 2: Run with the synthetic invalid manifest and confirm failure**

Run: `.\.toolchains\flutter\bin\dart.bat run tool/acceptance/validate_audio_dataset.dart --manifest test/fixtures/audio/invalid-manifest.json`

Expected: nonzero exit with specific speaker-count, sample-count, and checksum errors.

- [ ] **Step 3: Implement the protected-runner gate**

```powershell
.\.toolchains\flutter\bin\dart.bat run tool/acceptance/validate_audio_dataset.dart --manifest "$env:AUDIO_ACCEPTANCE_ROOT\manifest.json"
.\.toolchains\flutter\bin\dart.bat run tool/acceptance/audio_quality_gate.dart --dataset $env:AUDIO_ACCEPTANCE_ROOT --max-correct-fail-rate 0.03 --max-omission-pass-rate 0.01 --max-cold-start-ms 8000 --max-rtf 0.5 --long-session-minutes 30
```

The protected matrix runs inside each installed artifact on declared reference hardware and records platform, device model, CPU, RAM, OS, architecture, app/artifact hash, and model hash. Include at least one lower-midrange Android arm64 phone plus representative iPhone, Apple Silicon/Intel Mac, and Windows x64 devices. A desktop-host `dart run` result is a tool self-test, not four-platform performance evidence. After a 5-minute warm-up, the 30-minute test requires a drained speech queue, no missing segment numbers, RSS slope at most 1 MiB/minute, and final RSS at most 20 MiB above the warm-up point.

- [ ] **Step 4: Prove Android offline behavior automatically**

```powershell
$ErrorActionPreference = 'Stop'
try {
  adb shell cmd connectivity airplane-mode enable
  adb shell svc wifi disable
  adb shell svc data disable
  powershell -File tool\acceptance\assert_android_no_default_network.ps1
  .\.toolchains\flutter\bin\flutter.bat test integration_test/offline_smoke_test.dart -d emulator-5554
} finally {
  adb shell cmd connectivity airplane-mode disable
  adb shell svc wifi enable
  adb shell svc data enable
}
```

Expected: the OS reports no default network; browsing, recognition, judging, plans, statistics, export, and import work; dependency/native network logging records no socket attempt. The in-app recorder alone is insufficient. Signed iOS/macOS/Windows artifacts require retained firewall or physically disconnected lab evidence because ordinary hosted runners cannot honestly prove device-level disconnection.

- [ ] **Step 5: Commit**

```powershell
git add tool/acceptance integration_test/offline_smoke_test.dart integration_test/asr_acceptance_test.dart integration_test/long_session_test.dart docs/testing/private-audio-manifest.schema.json
git commit -m "test(release): gate offline asr quality and stability"
```

## Task 9: Gate accessibility, artifact manifests, and tagged releases

**Files:**
- Create: `test/accessibility/semantic_labels_test.dart`
- Create: `test/accessibility/large_text_test.dart`
- Create: `test/accessibility/color_redundancy_test.dart`
- Create: `integration_test/keyboard_navigation_test.dart`
- Create: `ios/RunnerUITests/AccessibilityTests.swift`
- Create: `tool/release/build_release_manifest.dart`
- Modify: `tool/release/verify_artifact.dart`
- Create: `test/release/release_manifest_test.dart`
- Create: `.github/workflows/release.yml`
- Modify: `docs/release/platform-acceptance.md`

**Interfaces:**
- Produces: checksummed release bundle, release manifest, and final go/no-go report.
- Consumes: artifacts/evidence from Tasks 1-8.

- [ ] **Step 1: Write failing accessibility and release-manifest tests**

Cover 320 logical pixels, 2.0 and 3.2 text scale, screen-reader labels, icon+text+color findings, desktop focus order, keyboard-only passage selection/recording/backup, and the absence of clipped primary actions. The manifest test requires source commit, exact toolchains, common input artifact name/digest, artifact name/platform/architecture/version/byte size, pre-sign payload SHA-256, final signed SHA-256, signer/identity/channel, Flutter revision, scripture/model hashes, signing/notarization status, and acceptance evidence hashes.

- [ ] **Step 2: Run and confirm failures**

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/accessibility
.\.toolchains\flutter\bin\flutter.bat test test/release/release_manifest_test.dart
```

Expected: FAIL until semantics and manifest builder are complete.

- [ ] **Step 3: Implement the final release workflow**

Every component workflow declares `on: workflow_call`. `release.yml` validates that a tag such as `v1.2.3` equals `v` plus the `pubspec.yaml` build name and reads build number `123` from the same version (`1.2.3+123`). In one caller run it composes reusable jobs with `needs`: quality → prepare inputs → Android/iOS/macOS/Windows. Platform workflows receive build name/number plus the common input artifact name/digest, upload uniquely named artifacts, and expose their digests. The final job downloads those same-run artifacts by name, never by a separately discovered workflow run ID, then verifies hashes/licenses/signing evidence and builds the manifest:

```powershell
.\.toolchains\flutter\bin\dart.bat run tool/release/build_release_manifest.dart --artifacts build/releases --evidence build/evidence --output build/releases/release-manifest.json
.\.toolchains\flutter\bin\dart.bat run tool/release/verify_artifact.dart --manifest build/releases/release-manifest.json
```

Do not publish automatically until a human confirms legal notices/model-license obligations, store metadata, private-corpus gate, real-device audio, TalkBack/VoiceOver/Narrator evidence, and credential-controlled signing status. Missing production Android/Apple/Windows credentials may produce a compile/test report but must block the corresponding user-distributable channel.

- [ ] **Step 4: Run the final local and platform gates**

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/accessibility
.\.toolchains\flutter\bin\flutter.bat test integration_test/keyboard_navigation_test.dart -d windows
.\.toolchains\flutter\bin\flutter.bat analyze --fatal-infos --fatal-warnings
.\.toolchains\flutter\bin\flutter.bat test
```

On macOS run `flutter test integration_test/keyboard_navigation_test.dart -d macos` and the iOS UI accessibility target against the workflow-selected simulator UDID. Expected: all automated gates pass and the release manifest names every artifact/evidence item with a valid SHA-256. Manual evidence has no unresolved blocker.

- [ ] **Step 5: Commit**

```powershell
git add test/accessibility integration_test/keyboard_navigation_test.dart ios/RunnerUITests tool/release/build_release_manifest.dart tool/release/verify_artifact.dart .github/workflows/release.yml docs/release/platform-acceptance.md
git commit -m "ci: add audited cross-platform release gate"
```

## Phase Acceptance

Run the quality suite and every platform workflow from the same Git commit. The phase is complete only when:

- Android APK/AAB, iOS app, macOS arm64/x64 apps, and Windows x64 MSIX are built from the same input artifact and contain identical scripture/model hashes.
- Production-signed channel artifacts pass identity/fingerprint/notarization checks. If owner credentials are absent, that distribution channel is explicitly blocked; unsigned or CI-test-signed artifacts are never represented as store-ready.
- Installed artifacts work with network/firewall disabled, declare no unnecessary network capability, and have no observed socket attempts in controlled evidence.
- Real notification, backup, microphone, ASR, and 30-minute stability gates meet their thresholds.
- Accessibility, licensing, provenance, artifact checksums, and manual platform evidence are complete.
- `git status --short` is empty after the final task commit.

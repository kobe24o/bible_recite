# Windows and macOS desktop support

**Goal:** Run the existing application on Windows and macOS, with both platforms tested, built and attached to the existing GitHub Release.

**Architecture:** Reuse the Flutter UI, SQLite data and offline speech model. Explicit desktop platform detection enables native notifications. Desktop recording follows the system default input; mobile microphone routing stays unchanged. macOS sandbox capabilities allow network, recording and user-selected file export.

**Scope:** Windows x64 installer and macOS DMG for testing. Do not claim certificate signing/notarization without configured credentials. Preserve unrelated working changes. Android's signed APK update feed remains unchanged; desktop users update through Releases.

- [x] Add failing platform, notification and desktop recording tests; run them before changing behavior.
- [x] Implement desktop detection, notification settings, audio routing and macOS capabilities; rerun focused tests.
- [x] Build macOS locally and fix compiler/dependency failures; run full tests and analyzer.
- [x] Add Windows/macOS native-runner test and release build jobs to the existing release workflow; package a Windows installer and macOS DMG with checksums. Release depends on both jobs.
- [ ] Document installation, build requirements, signing limitations and the remaining physical-device checks; review all changes and record verification.

Validation: Flutter 3.47.3; TZ=UTC flutter test; flutter analyze; flutter build macos --release; workflow syntax and packaging inspection. Windows native build and installer verification run on GitHub's Windows runner because this host is macOS.

## Verification record

- Full branch suite: 531 passed, 1 skipped.
- macOS native smoke test passed; release app built (universal arm64/x86_64).
- macOS codesign integrity verification passed; DMG created and verified locally.
- actionlint, YAML/Bash syntax and git diff whitespace checks passed.
- Analyzer reports 11 existing non-error notices; no new analyzer errors.
- Independent reviewer identified MSVC source encoding risk for the Chinese window title; fixed with Unicode escapes. No other actionable findings.
- Windows build and installer lifecycle verification are delegated to the GitHub Windows runner.

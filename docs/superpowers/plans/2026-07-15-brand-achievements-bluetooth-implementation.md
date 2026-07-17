# Brand, Punctuation, Achievements, and Bluetooth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a branded release APK with source-faithful punctuation, local encouragement achievements, and reliable Bluetooth-headset recording fallback.

**Architecture:** Keep comparison, rendering, achievements, and audio routing in independent testable units. Extend the existing local SQLite user repository additively, adapt the existing recorder behind a routing abstraction, and generate all launcher assets from one deterministic vector master.

**Tech Stack:** Flutter/Dart, Riverpod, sqlite3, record 7.1.1, Android AudioManager through record_android 2.1.2, SVG/PNG launcher assets, flutter_test.

## Global Constraints

- Recognition, punctuation reconstruction, achievements, and persistence remain fully offline.
- Punctuation, whitespace, and English case never affect accuracy.
- Existing plans and recitation history survive database migration.
- Bluetooth failure falls back once to the phone microphone and never loops.
- Reuse the existing Flutter, Android SDK, JDK, Gradle cache, and speech models.

---

### Task 1: Source-faithful punctuation projection

**Files:**
- Modify: `lib/src/features/recitation/domain/recitation_alignment.dart`
- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Modify: `test/recitation/recitation_alignment_test.dart`
- Modify: `test/recitation/recitation_practice_screen_test.dart`

**Interfaces:**
- Produces: `RecitationAlignment.displayTokens`, where comparable characters carry correctness state and punctuation/spacing carry `formatting` state.

- [ ] Add failing tests proving `神爱世人。` renders the final `。`, English spaces/case are preserved, punctuation is neutral, and accuracy is unchanged.
- [ ] Run `flutter test test/recitation/recitation_alignment_test.dart` and confirm the missing display projection fails.
- [ ] Add indexed normalization and project aligned operations back onto original target text.
- [ ] Render `displayTokens` in the practice screen with neutral punctuation and existing correctness colors.
- [ ] Run alignment and practice-screen tests and confirm they pass.

### Task 2: Encouragement achievement engine and UI

**Files:**
- Create: `lib/src/features/statistics/domain/achievement.dart`
- Create: `lib/src/features/statistics/domain/achievement_engine.dart`
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Create: `test/statistics/achievement_engine_test.dart`
- Modify: `test/statistics/statistics_repository_test.dart`
- Modify: `test/statistics/statistics_screen_test.dart`

**Interfaces:**
- Produces: `AchievementDefinition`, `AchievementProgress`, `AchievementEngine.evaluate(snapshot)`, repository unlock/list methods, and an achievement grid.

- [ ] Add failing rule tests for 1/3/10/25/50/100 sessions, 3/7/30 active-day streaks, 10/50/100 verses, 80/90/100 percent accuracy, first plan, and completed plan.
- [ ] Add a pure snapshot evaluator that returns newly satisfied achievement IDs and progress values.
- [ ] Add failing SQLite tests for additive migration, idempotent unlock, acquisition time, and historical backfill.
- [ ] Add `achievement_unlock` storage and aggregate queries; keep result/plan saves successful if evaluation fails.
- [ ] Add failing widget tests for locked/unlocked cards and the celebration dialog.
- [ ] Add the statistics achievement grid and show newly unlocked achievements after saving a recitation result.
- [ ] Run all statistics, plans, and recitation tests.

### Task 3: Bluetooth SCO routing and silent-input fallback

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/src/features/recitation/domain/speech_recognizer.dart`
- Modify: `lib/src/features/recitation/data/sherpa_streaming_recognizer.dart`
- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Create: `test/recitation/audio_input_routing_test.dart`
- Modify: `test/app/platform_configuration_test.dart`

**Interfaces:**
- Produces: `AudioInputSource` events, Bluetooth-SCO-first device selection, PCM activity monitoring, and one-shot phone-microphone fallback.

- [ ] Add a failing manifest test requiring `MODIFY_AUDIO_SETTINGS` beside `RECORD_AUDIO`.
- [ ] Add fake-recorder tests proving Bluetooth SCO is selected, A2DP-only devices use default input, and silent Bluetooth retries once without a device override.
- [ ] Add the Android permission and isolate recorder calls behind an injectable adapter.
- [ ] Emit the selected input source and render it on the practice screen.
- [ ] Track PCM peak activity; after two seconds of Bluetooth silence, stop and restart on the default microphone exactly once.
- [ ] Run platform and audio-routing tests.

### Task 4: Deterministic logo and launcher resources

**Files:**
- Create: `assets/branding/bible_recite_logo.svg`
- Create: `assets/branding/bible_recite_logo.png`
- Modify: `android/app/src/main/res/mipmap-*/ic_launcher.png`
- Create: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Create: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`
- Create: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- Create: `android/app/src/main/res/values/colors.xml`
- Modify: `android/app/src/main/res/drawable*/launch_background.xml`
- Modify: `ios/Runner/Assets.xcassets/AppIcon.appiconset/*`
- Modify: `pubspec.yaml`
- Modify: `test/app/platform_configuration_test.dart`

**Interfaces:**
- Produces: one vector source and platform-specific raster/adaptive assets with forest-green `#285943`, warm-gold `#E8B64C`, and ivory `#FFFDF5`.

- [ ] Add failing resource tests for adaptive icon XML, expected PNG sizes, and non-placeholder pixel content.
- [ ] Create the open-book and bookmark vector with an Android adaptive-icon safe zone.
- [ ] Render required PNG sizes from the vector using the bundled document/image runtime; do not alter speech-model assets.
- [ ] Update Android adaptive icons, legacy icons, iOS AppIcon, and launch backgrounds.
- [ ] Inspect the 1024 image and representative Android densities for clipping and legibility.
- [ ] Run platform resource tests.

### Task 5: Release verification and APK

**Files:**
- Modify only files required by failures found during verification.

**Interfaces:**
- Consumes all earlier deliverables and produces the final signed release APK.

- [ ] Run `dart format lib test`.
- [ ] Run `flutter test` and require zero failures.
- [ ] Run `flutter analyze` and require zero issues.
- [ ] Run `flutter build apk --release` with the remembered local SDK/JDK paths.
- [ ] Record the APK absolute path, byte size, SHA-256, and manual Bluetooth verification limitation if no device is connected.

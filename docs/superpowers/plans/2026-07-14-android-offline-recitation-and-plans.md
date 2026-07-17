# Android Offline Recitation and Plans Implementation Plan

> **Execution:** Implement inline in this task. For every behavior, add one failing test, run it, add the minimum production code, and rerun the affected suite. Preserve the existing uncommitted navigation and scripture-pack fixes.

**Goal:** Ship an Android arm64 APK that shows localized Bible book names, starts verse or continuous recitation from a chapter, recognizes Mandarin and English fully offline, explains differences, creates preset or custom 1–365 day plans, and persists Today/Plan/Statistics data locally.

**Architecture:** OSIS IDs and scripture revision hashes remain stable storage keys. Pure Dart owns book-name lookup, normalization/alignment, plan generation, review scheduling, session state, and SQLite persistence. `sherpa_onnx` owns the bilingual streaming runtime behind `OfflineSpeechRecognizer`; UI and domain code never import Sherpa types.

**Pinned stack:** Flutter 3.44.4, Dart 3.12.2, Riverpod 3.3.2, GoRouter 17.3.0, sqlite3 3.3.4, `sherpa_onnx` 1.13.4, `record` 7.1.1, Android minSdk 24, release ABI `arm64-v8a`.

**Pinned model:** `sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20`, using its INT8 encoder and joiner, FP32 decoder, and `tokens.txt`. The build bundles these assets; the installed app never downloads a model.

## Global acceptance rules

- Scripture packs stay read-only and replaceable through `ScriptureRepository`; user state goes in a separate `user.sqlite`.
- UI resolves `GEN`, `MAT`, etc. through one locale-aware catalog. Routes and database rows continue to store OSIS IDs.
- Recognition infrastructure failures never become failed memorization attempts.
- Every saved attempt references translation ID, pack ID, versification ID, and semantic SHA-256.
- The release manifest has no Internet permission and the app works after a fresh install in airplane mode.
- Completion requires analysis, all tests, an arm64 release APK, APK inspection, and device/emulator smoke tests.

## Task 1: Stabilize the current baseline

**Files:** existing dirty files under `lib/l10n/`, `lib/src/app/`, dashboard/plans/statistics presentation, `scripture_pack_installer.dart`, `test/app/app_navigation_test.dart`, and `test/scripture/scripture_pack_installer_test.dart`.

1. Run:

   ```powershell
   .\.toolchains\flutter\bin\flutter.bat test test\app\app_navigation_test.dart test\scripture\scripture_pack_installer_test.dart
   .\.toolchains\flutter\bin\flutter.bat analyze
   ```

2. Fix only regressions caused by the dirty baseline and run the full suite.
3. Commit this coherent baseline before adding features: `fix: restore offline scripture navigation`.

## Task 2: Add one localized canon catalog

**Files:**

- Modify: `assets/scripture/canon/protestant66.json`, `pubspec.yaml`
- Create: `lib/src/features/scripture/domain/book_name_catalog.dart`
- Create: `lib/src/features/scripture/data/asset_book_name_catalog.dart`
- Modify: scripture providers, browser, and passage screens
- Create: `test/scripture/book_name_catalog_test.dart`
- Modify: browser and passage widget tests

1. Add failing tests covering `GEN`, `PSA`, `MAT`, `JHN`, `PHP`, and `REV` in `zh-Hans`, `zh-Hant`, and `en`; unknown locale falls back to English, unknown OSIS ID to the ID.
2. Replace each two-element canon row with an object containing `osisId`, `chapterCount`, and complete `names` for all 66 books.
3. Implement:

   ```dart
   abstract interface class BookNameCatalog {
     String nameFor(String osisId, Locale locale);
     String chapterLabel(String osisId, int chapter, Locale locale);
   }
   ```

4. Provide the catalog through Riverpod. Replace OSIS IDs in book tiles, selected-book headers, passage titles, plan tasks, and statistics labels. Keep IDs in routes and repository calls.
5. Run focused tests and the full suite; commit `feat: localize Bible book names`.

## Task 3: Add deterministic, explainable comparison

**Files:**

- Create: `lib/src/features/recitation/domain/recognition_models.dart`
- Create: `lib/src/features/recitation/domain/speech_recognizer.dart`
- Create: `lib/src/features/recitation/domain/text_normalizer.dart`
- Create: `lib/src/features/recitation/domain/sequence_aligner.dart`
- Create: `lib/src/features/recitation/domain/recitation_evaluator.dart`
- Create: matching tests under `test/recitation/`

1. Add failing tests for Chinese punctuation/spacing, common spoken numbers, simplified/traditional equivalence, English punctuation/case, omissions, insertions, substitutions, local reorder, self-correction, and unresolved partial text.
2. Define the cross-platform recognition boundary:

   ```dart
   sealed class RecognitionEvent {}
   final class RecognitionPartial extends RecognitionEvent { final String text; }
   final class RecognitionFinal extends RecognitionEvent { final String text; }
   final class RecognitionFailure extends RecognitionEvent {
     final RecognitionFailureKind kind;
     final String message;
   }

   abstract interface class OfflineSpeechRecognizer {
     Stream<RecognitionEvent> get events;
     Future<void> initialize();
     Future<void> start({required String languageTag});
     Future<void> pause();
     Future<void> resume();
     Future<void> stop();
     Future<void> dispose();
   }
   ```

3. Normalize temporary comparison tokens while retaining target source spans. Never mutate displayed scripture.
4. Implement monotonic dynamic-programming alignment producing `match`, `insert`, `omit`, `replace`, `reorder`, `selfCorrected`, and `uncertain` findings.
5. Classify results as `accuratePass`, `passNeedsReview`, or `needsPractice`. Uncertain audio requests repetition and is not scored wrong.
6. Run focused/full tests; commit `feat: add explainable recitation evaluator`.

## Task 4: Bundle Sherpa-ONNX bilingual streaming ASR

**Files:**

- Modify: `pubspec.yaml`, Android manifest and Gradle configuration
- Create: `tool/models/streaming-zipformer-bilingual.json`
- Create: `tool/fetch_sherpa_model.ps1`
- Create: `lib/src/features/recitation/data/sherpa_model_config.dart`
- Create: `lib/src/features/recitation/data/sherpa_streaming_recognizer.dart`
- Create: microphone PCM source interface and `record` adapter
- Create: Sherpa configuration and contract tests

1. Add exact dependencies `sherpa_onnx: 1.13.4` and `record: 7.1.1`.
2. Pin the official archive URL:

   `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2`

3. The fetcher downloads to temp, computes archive SHA-256 and byte size, extracts to temp, copies only the INT8 encoder, FP32 decoder, INT8 joiner, tokens, and upstream license/readme, records their hashes in the manifest, then atomically replaces `assets/models/sherpa/current`. Subsequent runs must reject mismatched bytes/hashes.
4. Add failing tests proving 16 kHz mono input, four decoding threads, greedy search, endpointing, selected INT8 paths, and no runtime URL.
5. Implement one initialized `OnlineRecognizer`: feed Float32 samples, decode while ready, emit changed partial text, emit/reset final text on endpoint, and free stream/recognizer exactly once.
6. Request only `RECORD_AUDIO`; do not add Internet permission. Restrict release ABI to arm64.
7. Contract-test with a fake PCM source, then run one Mandarin and one English WAV fixture through the real model. Commit `feat: add offline bilingual speech recognition`.

## Task 5: Build the recitation session and screens

**Files:**

- Create: recitation session controller/state/providers
- Create: mode sheet, practice screen, and result screen
- Modify: passage screen, router, and localization ARB/generated files
- Create: controller and widget-flow tests

1. Add failing tests for idle → initializing → listening → paused → evaluating → completed, permission/model/audio failures, cancellation, illegal transitions, and no saved attempt on infrastructure failure.
2. Add visible `开始背诵` and `加入计划` buttons after passage data loads. Start opens verse/continuous mode selection and routes with an exact `PassageSelection`, translation revision, and immutable target text.
3. Hide scripture by default. Show localized range, offline badge, timer, live transcript, current progress, pause/resume, first-character hint, next-word hint, reveal, finish, and cancel.
4. Verse mode evaluates each verse before advancing. Continuous mode evaluates the concatenated range and maps findings back to verse spans.
5. Results render evidence against authoritative text and offer retry-errors, retry-all, and finish.
6. Pause capture on lifecycle pause; confirm route cancellation; release all audio/model resources.
7. Run localization generation, focused/full tests; commit `feat: add offline recitation flow`.

## Task 6: Create the local progress database

**Files:**

- Create: progress domain models/repository
- Create: `lib/src/features/progress/data/user_database.dart`
- Create: `lib/src/features/progress/data/sqlite_progress_repository.dart`
- Create: progress Riverpod providers
- Create: migration/repository tests

1. Write failing tests using temporary databases.
2. Create `user.sqlite`, foreign keys on, `user_version = 1`, with tables for plans, tasks, task verses, attempts, attempt findings, verse mastery, and review queue.
3. Store revision identity, OSIS verse key, UTC timestamp, local date, mode, outcome, duration, hints, and structured findings. Never store display names or audio paths.
4. Save attempt, findings, mastery, and review scheduling in one transaction. Accurate completion schedules 1, 3, 7, 14, and 30 days; failure schedules next-day practice without advancing mastery.
5. Expose queries/streams for Today, active plans, pass counts, streak, mastery, due review, and daily trend.
6. Prove restart persistence, rollback on failure, and wording-specific mastery identity; commit `feat: persist recitation progress locally`.

## Task 7: Add preset and custom plans

**Files:**

- Create: plan models, presets, generator, and controller
- Create: plan-creation sheet
- Replace: current plans placeholder screen
- Modify: passage screen add-to-plan flow
- Create: generator and flow tests

1. Add failing tests for Psalm 23/7 days, Matthew 5–7/14 days, John 1–3/21 days, and Philippians/30 days.
2. Support a custom same-book chapter range and integer days from 1 through 365.
3. Load verses through `ScriptureRepository`, weight by normalized character/word count, and partition in canonical order with minimum cumulative-weight deviation. Include every verse exactly once.
4. Persist plan/task creation transactionally. Show localized cards with progress, next task, dates, and status.
5. `加入计划` preselects the current chapter while allowing range/day edits.
6. Run focused/full tests; commit `feat: add memorization plans`.

## Task 8: Show real Today and Statistics data

**Files:**

- Replace: Today and Statistics placeholder screens
- Create: Today and Statistics controllers
- Create: corresponding widget tests

1. Add failing tests for new content, due review, failed retry, deduplication, empty states, plan progress, pass rate, streak, mastered verses, due count, and recent trend.
2. Merge same-day items by revision + verse key, prioritizing failed retry, then review, then new content.
3. Route a Today item into recitation with its exact range.
4. Compute statistics only from local attempts/mastery; cancelled and infrastructure failures do not enter the pass-rate denominator.
5. Run focused/full tests; commit `feat: show today tasks and statistics`.

## Task 9: Verify offline Android release and build APK

**Files:**

- Create: `integration_test/offline_android_flow_test.dart`
- Modify: `README.md`
- Create: `docs/verification/2026-07-14-android-offline-acceptance.md`

1. Run:

   ```powershell
   .\.toolchains\flutter\bin\dart.bat format lib test integration_test tool
   .\.toolchains\flutter\bin\flutter.bat gen-l10n
   .\.toolchains\flutter\bin\flutter.bat analyze
   .\.toolchains\flutter\bin\flutter.bat test
   ```

2. Build:

   ```powershell
   $env:ANDROID_HOME='C:\Users\mingm\AppData\Local\Android\sdk'
   $env:JAVA_HOME='D:\Program Files\JetBrains\Android Studio\jbr'
   .\.toolchains\flutter\bin\flutter.bat build apk --release --target-platform android-arm64
   ```

3. Verify signature, ABI, 180–300 MB target size, absence of unused models/ABIs, no Internet permission, and calculate SHA-256.
4. Fresh-install with network disabled. Verify Chinese names/title, Mandarin and English recognition, verse and continuous results, one preset and one custom plan, Today, Statistics, and cold-restart persistence.
5. Record device/API/model/package/hash evidence. If emulator microphone injection is unavailable, run deterministic Mandarin/English PCM fixtures through the release recognizer and separately verify live permission/capture on a device.
6. Commit `test: verify offline Android release`.

## Completion gate

- `flutter analyze` and all tests pass.
- Release APK is signed arm64, target 180–300 MB, with recorded SHA-256.
- App works after install with network disabled and has no Internet permission.
- Chinese locale does not expose OSIS IDs as primary titles.
- Passage screen offers recitation and plan actions.
- Mandarin/English recognition, explainable comparison, four presets, custom 1–365 days, Today, plans, and statistics survive a cold restart.

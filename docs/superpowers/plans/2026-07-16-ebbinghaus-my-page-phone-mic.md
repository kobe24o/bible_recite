# Ebbinghaus Review, My Page, and Phone Microphone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable local Ebbinghaus chapter reviews to the renamed “My” page and force recording through the phone microphone.

**Architecture:** Keep automatic reviews separate from editable memorization plans. A pure scheduler defines the 1/2/4/7/15/30-day nodes, while `SqlitePlanRepository` persists settings, cycles, and review nodes and merges due review items into Today. `reviewId` flows from Today to Passage to Recitation so a result can complete or restart the correct cycle.

**Tech Stack:** Flutter, Riverpod, GoRouter, sqlite3, record, flutter_test.

## Global Constraints

- Review offsets are exactly `1, 2, 4, 7, 15, 30` days.
- Passing means `accuracy >= threshold`; default threshold is `80%` and allowed range is `50%–100%`.
- Disabling does not delete history and re-enabling does not revive old cycles.
- Recording must use the built-in phone microphone with Android Bluetooth management disabled.
- Release version is `1.0.2+3` and the APK filename includes this version.

---

### Task 1: Ebbinghaus domain model and schedule

**Files:**
- Create: `lib/src/features/review/domain/ebbinghaus_models.dart`
- Create: `lib/src/features/review/domain/ebbinghaus_scheduler.dart`
- Test: `test/review/ebbinghaus_scheduler_test.dart`

**Interfaces:**
- Produces: `EbbinghausSettings`, `EbbinghausReview`, and `EbbinghausScheduler.schedule(DateTime)`.

- [ ] Write a failing test asserting offsets `[1, 2, 4, 7, 15, 30]` and `0.80` threshold boundary behavior.
- [ ] Run `flutter test test/review/ebbinghaus_scheduler_test.dart` and confirm missing-type failures.
- [ ] Implement immutable models and the pure scheduler with `passes(accuracy, threshold)` using `>=`.
- [ ] Re-run the scheduler test and confirm it passes.

### Task 2: SQLite settings, cycles, and idempotent review processing

**Files:**
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart`
- Test: `test/review/ebbinghaus_repository_test.dart`

**Interfaces:**
- Produces: `getEbbinghausSettings()`, `updateEbbinghausSettings(...)`, `processEbbinghausResult(resultId:, reviewId:)`, and `dueEbbinghausReviews(date)`.

- [ ] Write failing repository tests for the 80% default, enabling timestamp, six review nodes, equality at threshold, idempotency, failure restart, disable hiding, and no revival after re-enable.
- [ ] Run the repository tests and confirm schema/API failures.
- [ ] Add settings, cycle, and review tables with foreign keys, status fields, uniqueness constraints, and `user_version = 4`.
- [ ] Implement transactional scheduling: proactive passed results create one active cycle; passed review completes its node; failed review cancels future nodes and creates a new cycle based on failure day.
- [ ] Implement disabled-cycle pausing and due-review filtering.
- [ ] Re-run repository and existing plan/statistics repository tests.

### Task 3: Rename Statistics to My and add settings UI

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/src/app/responsive_shell.dart`
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Modify: generated localization files via `flutter gen-l10n`
- Test: `test/app/app_localization_test.dart`
- Test: `test/statistics/statistics_screen_test.dart`

**Interfaces:**
- Consumes: repository settings APIs from Task 2.

- [ ] Write failing widget tests expecting “我的”, a visible switch with no statistics, default `80%`, and persisted threshold edits.
- [ ] Run the widget tests and confirm missing-label/settings failures.
- [ ] Change navigation and title copy to My/我的/我的 and use an account icon.
- [ ] Add a settings card above statistics with Switch, integer Slider from 50–100, default 80%, and interval text.
- [ ] Keep settings visible when results and achievements are empty; render the old empty message only inside the statistics section.
- [ ] Generate localizations and re-run widget/navigation tests.

### Task 4: Show review items in Today and carry review identity

**Files:**
- Modify: `lib/src/features/dashboard/presentation/today_screen.dart`
- Modify: `lib/src/app/router.dart`
- Modify: `lib/src/features/scripture/presentation/passage_screen.dart`
- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Test: `test/dashboard/today_screen_test.dart`
- Test: `test/recitation/recitation_practice_screen_test.dart`

**Interfaces:**
- Adds nullable `reviewId` to `PassageScreen` and `RecitationRequest`.
- Consumes: `dueEbbinghausReviews` and `processEbbinghausResult`.

- [ ] Write failing tests that a due review appears in Today, opens the full chapter, and passes its review ID into recitation.
- [ ] Run tests and confirm review task is absent.
- [ ] Load plan tasks and Ebbinghaus reviews together and render distinct review cards without manual completion checkboxes.
- [ ] Pass `reviewId` through route extra and recitation request.
- [ ] After saving a result, invoke idempotent review processing; on scheduler failure preserve the result and show an error.
- [ ] Re-run dashboard, passage, recitation, and repository tests.

### Task 5: Force phone microphone routing

**Files:**
- Modify: `lib/src/features/recitation/domain/audio_input_routing.dart`
- Modify: `lib/src/features/recitation/data/sherpa_streaming_recognizer.dart`
- Test: `test/recitation/audio_input_routing_test.dart`
- Test: `test/app/platform_configuration_test.dart`

**Interfaces:**
- Produces: `AudioInputRouting.phoneMicrophone(devices)` only; recording uses `manageBluetooth: false` and `AndroidAudioSource.mic`.

- [ ] Replace the current Bluetooth-preference test with a failing test that built-in wins even when Bluetooth SCO is connected.
- [ ] Run the routing test and confirm it fails against the current preference.
- [ ] Remove Bluetooth selection, silence timer, and fallback restart; start once with the built-in device and Bluetooth management disabled.
- [ ] Emit a phone-microphone input label and re-run recitation tests.

### Task 6: Version, full verification, and APK

**Files:**
- Modify: `pubspec.yaml`
- Modify: `test/app/platform_configuration_test.dart`
- Output: `build/app/outputs/flutter-apk/BibleRecite-1.0.2+3.apk`

**Interfaces:**
- Produces the installable, versioned Android artifact.

- [ ] Update version test first to expect `1.0.2+3` and verify it fails.
- [ ] Set `version: 1.0.2+3` and verify the test passes.
- [ ] Run `dart format lib test`.
- [ ] Run the complete `flutter test` suite and require zero failures.
- [ ] Run `flutter analyze` and require “No issues found”.
- [ ] Build with `tool/build_versioned_apk.ps1 -SkipVersionBump`.
- [ ] Verify APK badging reports versionName `1.0.2`, versionCode `3`, signature verification succeeds, and calculate SHA-256.

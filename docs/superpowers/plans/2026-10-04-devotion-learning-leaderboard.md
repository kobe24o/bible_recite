# Devotion Learning and Leaderboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record daily devotion reading and notes as local learning data, surface their completion state in today/reminders, and rank four devotion aggregates safely through Supabase.

**Architecture:** Persist one local aggregate row per local calendar day, then derive completion and streak statistics from its immutable `completed_at` marker. A foreground-only session tracker flushes elapsed seconds at lifecycle boundaries; UI and reminders read the same repository state. Extend the existing delayed `LeaderboardSnapshot` protocol with four fields, retaining the Supabase RPC security boundary and a backwards-compatible old RPC overload.

**Tech Stack:** Flutter/Dart, Riverpod, SQLite (`sqlite3`), Flutter local notifications, Supabase Postgres/RLS/RPC, pgTAP, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-04-devotion-learning-leaderboard-design.md`

## Global Constraints

- Count only foreground time inside a same-day devotion `PassageScreen`; detail-page and background time never count.
- A day completes only when active time is strictly greater than 60 seconds or a non-empty note is saved for that same local day; it remains completed thereafter.
- Never send notes, elapsed-event rows, or a service-role key to Supabase; only the four resulting aggregates join the existing snapshot.
- Preserve the existing 15-minute upload throttle and 5-minute per-metric read cache.
- Keep direct writes to public leaderboard tables forbidden; all RPC authorization continues to require an authenticated anonymous or signed-in user.
- Maintain the existing user-owned dirty files and stage only files named in each task.

## Review Focus

- Exactly 60 seconds must remain incomplete; 61 seconds must complete exactly once (Task 1).
- App pause, lock, and resume must never add background time (Task 2).
- A reader kept open across midnight must not create a next-day completion or duration (Task 2).
- An old application build submitting the ten-parameter RPC must preserve an existing user’s devotion values (Task 7).
- A today page with only unfinished devotion must render the pending state and schedule one reminder rather than appearing empty (Tasks 4 and 5).

---

### Task 1: Persist daily devotion activity and derive statistics

**Files:**
- Create: `lib/src/features/devotion/domain/devotion_activity.dart`
- Modify: `lib/src/features/plans/data/sqlite_plan_repository.dart:188-203,1210-1270`
- Modify: `lib/src/features/devotion/domain/devotion_models.dart`
- Test: `test/devotion/sqlite_devotion_repository_test.dart`

**Interfaces:**
- Produces `DevotionStats({required int devotionDays, required int totalSeconds, required int currentDayStreak, required int maxDayStreak})`.
- Produces `Future<void> SqlitePlanRepository.recordDevotionReading(DateTime day, int activeSeconds, {DateTime? recordedAt})`.
- Produces `Future<void> SqlitePlanRepository.completeDevotionFromNote(DateTime day, {DateTime? completedAt})`, `Future<bool> isDevotionCompleted(DateTime day)`, and `Future<DevotionStats> getDevotionStats(DateTime now)`.
- `saveDevotionNote` calls `completeDevotionFromNote` only for a non-empty note whose normalized date is today.

- [ ] **Step 1: Write failing repository tests for threshold, note completion, daily uniqueness, and streaks**

```dart
test('61 active seconds completes today once while 60 seconds does not', () async {
  await repository.recordDevotionReading(today, 60, recordedAt: now);
  expect(await repository.isDevotionCompleted(today), isFalse);
  await repository.recordDevotionReading(today, 1, recordedAt: now);
  expect((await repository.getDevotionStats(now)).devotionDays, 1);
});
```

Add tests proving a non-empty same-day note completes the day; clearing it does not undo completion; and sparse completed dates yield the correct current/max streak values.

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `flutter test test/devotion/sqlite_devotion_repository_test.dart`

Expected: FAIL because activity persistence and `DevotionStats` do not exist.

- [ ] **Step 3: Add the activity domain model and SQLite aggregate implementation**

Create `devotion_activity` with normalized `date` primary key, non-negative `active_seconds`, nullable `completed_at`, and `updated_at`. Add migration-safe table creation to repository initialization. Use a transaction to increment seconds, set `completed_at` when cumulative seconds exceed 60, and call `markLeaderboardDirty()` only after an actual aggregate change. Calculate streaks from completed dates ending at the supplied local day.

- [ ] **Step 4: Make today-only note completion explicit in `saveDevotionNote`**

Use the same date-normalization helper as notes. Empty-note deletion must not erase activity/completion; a non-empty note for today marks the day complete after the note write succeeds.

- [ ] **Step 5: Run repository tests to verify they pass**

Run: `flutter test test/devotion/sqlite_devotion_repository_test.dart`

Expected: PASS, including existing note-history behavior.

- [ ] **Step 6: Commit the independently tested persistence work**

```bash
git add lib/src/features/devotion/domain/devotion_activity.dart lib/src/features/devotion/domain/devotion_models.dart lib/src/features/plans/data/sqlite_plan_repository.dart test/devotion/sqlite_devotion_repository_test.dart
git commit -m "feat: track daily devotion learning activity"
```

### Task 2: Add a foreground-only devotion reading session tracker

**Files:**
- Create: `lib/src/features/devotion/application/devotion_reading_session.dart`
- Modify: `lib/src/features/devotion/application/devotion_providers.dart`
- Test: `test/devotion/devotion_reading_session_test.dart`

**Interfaces:**
- Produces `DevotionReadingSession({required DateTime day, required DateTime Function() clock, required Future<void> Function(DateTime day, int seconds) onElapsed})`.
- Provides `start()`, `pause()`, `resume()`, `stop()`, and `dispose()`; each method is idempotent.
- A completed flush invokes `onElapsed` once with only accumulated active whole seconds and never with zero.

- [ ] **Step 1: Write failing pure-Dart tracker tests**

```dart
test('pause excludes background duration and stop flushes active seconds', () async {
  session.start();
  now = now.add(const Duration(seconds: 40));
  await session.pause();
  now = now.add(const Duration(hours: 2));
  session.resume();
  now = now.add(const Duration(seconds: 21));
  await session.stop();
  expect(flushed, [61]);
});
```

Add tests for duplicate pause/stop calls and a day change that stops instead of attributing elapsed time to tomorrow.

- [ ] **Step 2: Run tracker tests to verify they fail**

Run: `flutter test test/devotion/devotion_reading_session_test.dart`

Expected: FAIL because `DevotionReadingSession` does not exist.

- [ ] **Step 3: Implement the tracker without Flutter widget dependencies**

Use an injected wall clock. Keep the active start instant nullable, accumulate only positive whole seconds, and call the supplied callback serially so a lifecycle pause cannot race a route pop. Stop permanently after a calendar-day mismatch.

- [ ] **Step 4: Run tracker tests to verify they pass**

Run: `flutter test test/devotion/devotion_reading_session_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the tracker**

```bash
git add lib/src/features/devotion/application/devotion_reading_session.dart lib/src/features/devotion/application/devotion_providers.dart test/devotion/devotion_reading_session_test.dart
git commit -m "feat: measure foreground devotion reading sessions"
```

### Task 3: Wire timed reading and notes into devotion pages

**Files:**
- Modify: `lib/src/features/devotion/presentation/devotion_detail_screen.dart`
- Modify: `lib/src/features/scripture/presentation/passage_screen.dart`
- Modify: `lib/src/features/devotion/application/devotion_providers.dart`
- Test: `test/devotion/devotion_detail_screen_test.dart`
- Test: `test/scripture/passage_screen_test.dart`

**Interfaces:**
- `PassageScreen` gains optional `DateTime? devotionActivityDay`; null keeps all existing routes unchanged.
- With `devotionActivityDay`, `PassageScreen` registers a lifecycle observer and owns a `DevotionReadingSession`; it calls repository `recordDevotionReading` on flush.
- `DevotionDetailScreen` supplies the field only when `widget.date` equals `devotionTodayProvider` and refreshes `devotionRevisionProvider` after a note or reader session can change activity.

- [ ] **Step 1: Write failing widget tests for same-day wiring**

Add a detail-screen test that opens today’s scripture and asserts the constructed reader receives activity context. Add a passage-screen lifecycle test that simulates `paused`, `resumed`, and route disposal, then asserts only active seconds reach the repository.

- [ ] **Step 2: Run the focused widget tests to verify they fail**

Run: `flutter test test/devotion/devotion_detail_screen_test.dart test/scripture/passage_screen_test.dart`

Expected: FAIL because no devotion activity context/session exists.

- [ ] **Step 3: Implement the optional reader context and lifecycle bridge**

In `PassageScreen`, implement `WidgetsBindingObserver`, begin after initial route construction, pause on `inactive`, `paused`, and `detached`, resume only on `resumed`, and flush/dispose before unregistering. Do not add tracking to ordinary Bible, plan, review, or historical-devotion readers.

- [ ] **Step 4: Refresh detail state after a qualifying note or returned reader**

Await the reader route in `DevotionDetailScreen`, invalidate/revision-refresh activity consumers after it returns, and retain current note-save error behavior.

- [ ] **Step 5: Run focused page tests to verify they pass**

Run: `flutter test test/devotion/devotion_detail_screen_test.dart test/scripture/passage_screen_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit page integration**

```bash
git add lib/src/features/devotion/presentation/devotion_detail_screen.dart lib/src/features/scripture/presentation/passage_screen.dart lib/src/features/devotion/application/devotion_providers.dart test/devotion/devotion_detail_screen_test.dart test/scripture/passage_screen_test.dart
git commit -m "feat: count foreground devotion reading"
```

### Task 4: Show devotion completion as a first-class today task

**Files:**
- Modify: `lib/src/features/dashboard/presentation/today_screen.dart`
- Test: `test/dashboard/today_screen_test.dart` (create if absent)
- Test: `test/app/app_navigation_test.dart`

**Interfaces:**
- `_TodayData` gains `bool devotionCompleted` and an optional completed-reason value derived from `DevotionStats`/today note state.
- `_allTodayCompleted(SqlitePlanRepository repository, {required bool hasTodayDevotion})` additionally requires completed devotion when a schedule entry exists.

- [ ] **Step 1: Write failing today-page tests for both visual states**

Assert a scheduled unfinished devotion appears in “待完成” with `today-devotion-YYYY-MM-DD`, `待完成`, and a chevron. Seed a completed activity, rebuild, and assert the card appears under “今日已完成” with a green check and completion reason. Add the single-devotion case so the page is never `_EmptyToday`.

- [ ] **Step 2: Run the today tests to verify they fail**

Run: `flutter test test/dashboard/today_screen_test.dart test/app/app_navigation_test.dart`

Expected: FAIL because devotion is currently rendered as an ungrouped static card.

- [ ] **Step 3: Implement grouped devotion card and return refresh**

Load `isDevotionCompleted` in `_load`; place a reusable private devotion card in pending or complete arrays alongside task/review sections. Await `context.push` for its route and increment `_revision` after return. Include devotion in the empty-state and all-complete conditions only when the day has a schedule entry.

- [ ] **Step 4: Run the today tests to verify they pass**

Run: `flutter test test/dashboard/today_screen_test.dart test/app/app_navigation_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit today-page behavior**

```bash
git add lib/src/features/dashboard/presentation/today_screen.dart test/dashboard/today_screen_test.dart test/app/app_navigation_test.dart
git commit -m "feat: show devotion completion in today tasks"
```

### Task 5: Include unfinished devotion in daily reminders and learning statistics

**Files:**
- Modify: `lib/src/features/reminder/daily_task_reminder.dart`
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Test: `test/reminder/daily_task_reminder_test.dart`
- Test: `test/statistics/statistics_screen_test.dart`

**Interfaces:**
- Extract `int pendingLearningItemCount({required int tasks, required int reviews, required bool devotionPending})` for deterministic reminder testing.
- `_StatisticsData` gains `DevotionStats devotion` and the learning-data view renders its four values.

- [ ] **Step 1: Write failing reminder and statistics tests**

```dart
test('one unfinished devotion counts as a learning reminder', () {
  expect(pendingLearningItemCount(tasks: 0, reviews: 0, devotionPending: true), 1);
});
```

Add a scheduler test that confirms no future notification when all three sources are complete, plus a statistics widget assertion for cumulative duration and both devotion streak labels.

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `flutter test test/reminder/daily_task_reminder_test.dart test/statistics/statistics_screen_test.dart`

Expected: FAIL because reminder count ignores devotion and statistics have no devotion block.

- [ ] **Step 3: Implement the shared completion-aware reminder count**

Have `reschedule` determine whether today has a cached scheduled devotion and query `isDevotionCompleted` only when it does. Use `pendingLearningItemCount` and the exact Chinese body `今天还有 N 项学习任务未完成`; do not schedule anything when count is zero.

- [ ] **Step 4: Render the learning-data devotion block**

Load `getDevotionStats(DateTime.now())` in statistics data and add a concise four-value section adjacent to existing recitation learning cards. Preserve existing localized paths and all existing statistics content.

- [ ] **Step 5: Run focused tests to verify they pass**

Run: `flutter test test/reminder/daily_task_reminder_test.dart test/statistics/statistics_screen_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit reminder and statistics work**

```bash
git add lib/src/features/reminder/daily_task_reminder.dart lib/src/features/statistics/presentation/statistics_screen.dart test/reminder/daily_task_reminder_test.dart test/statistics/statistics_screen_test.dart
git commit -m "feat: include devotion in learning reminders and statistics"
```

### Task 6: Add devotion aggregates to local leaderboard models and UI

**Files:**
- Modify: `lib/src/features/leaderboard/domain/leaderboard_models.dart`
- Modify: `lib/src/features/leaderboard/application/leaderboard_snapshot_builder.dart`
- Modify: `lib/src/features/leaderboard/application/leaderboard_providers.dart`
- Modify: `lib/src/features/leaderboard/data/leaderboard_codec.dart`
- Modify: `lib/src/features/leaderboard/presentation/leaderboard_screen.dart`
- Test: `test/leaderboard/leaderboard_snapshot_builder_test.dart`
- Test: `test/leaderboard/supabase_leaderboard_gateway_test.dart`
- Test: `test/leaderboard/leaderboard_screen_test.dart`

**Interfaces:**
- Add `devotionDays`, `totalDevotionSeconds`, `maxDevotionDayStreak`, and `currentDevotionDayStreak` to `LeaderboardSnapshot`.
- Add four matching `LeaderboardMetric` values/wire names: `devotion_days`, `total_devotion_seconds`, `max_devotion_day_streak`, `current_devotion_day_streak`.
- `buildLeaderboardSnapshot` accepts `required DevotionStats devotion`.

- [ ] **Step 1: Write failing snapshot, encoding, and screen-order tests**

Assert the snapshot gets all four values from a supplied `DevotionStats`; assert RPC encoding sends only the four aggregate values in addition to existing fields; assert chips appear in the exact approved order and labels distinguish `最高连续背诵天数` / `当前连续背诵天数` from their 灵修 counterparts.

- [ ] **Step 2: Run focused leaderboard tests to verify they fail**

Run: `flutter test test/leaderboard/leaderboard_snapshot_builder_test.dart test/leaderboard/supabase_leaderboard_gateway_test.dart test/leaderboard/leaderboard_screen_test.dart`

Expected: FAIL because the metrics, snapshot properties, labels, and payload fields do not exist.

- [ ] **Step 3: Extend models, snapshot loading, and cache-safe codec**

Load `getDevotionStats` in `loadLeaderboardSnapshot`, pass it into the builder, and ensure every new metric is supported by `valueFor`, `wireName`, formatter, cache key, and serializable snapshot payload.

- [ ] **Step 4: Order and name all leaderboard chips exactly as approved**

Keep recitation duration before the adjacent recitation maximum/current streak pair; then use devotion count/duration followed by adjacent devotion maximum/current streak pair; retain badge count and quiz accuracy last.

- [ ] **Step 5: Run focused leaderboard tests to verify they pass**

Run: `flutter test test/leaderboard/leaderboard_snapshot_builder_test.dart test/leaderboard/supabase_leaderboard_gateway_test.dart test/leaderboard/leaderboard_screen_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit the local leaderboard extension**

```bash
git add lib/src/features/leaderboard/domain/leaderboard_models.dart lib/src/features/leaderboard/application/leaderboard_snapshot_builder.dart lib/src/features/leaderboard/application/leaderboard_providers.dart lib/src/features/leaderboard/data/leaderboard_codec.dart lib/src/features/leaderboard/presentation/leaderboard_screen.dart test/leaderboard/leaderboard_snapshot_builder_test.dart test/leaderboard/supabase_leaderboard_gateway_test.dart test/leaderboard/leaderboard_screen_test.dart
git commit -m "feat: rank devotion learning aggregates"
```

### Task 7: Safely migrate Supabase leaderboard RPCs and verify security

**Files:**
- Create: the single migration file generated by `supabase migration new devotion_leaderboard`
- Modify: `supabase/tests/leaderboard.sql`

**Interfaces:**
- New public overload: `submit_leaderboard_snapshot(text,text,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint,bigint)`.
- Existing ten-parameter public overload remains callable and preserves the caller’s existing devotion columns.
- `get_leaderboard` accepts the four approved devotion metric wire names.

- [ ] **Step 1: Write failing pgTAP cases for new metric and legacy compatibility**

Add tests that submit all fourteen aggregates, reject lower `devotion_days`, `total_devotion_seconds`, and `max_devotion_day_streak`, permit lower current devotion streak, return a `devotion_days` board, and verify a legacy ten-score submission leaves seeded devotion columns intact. Retain existing unauthenticated/RLS/raw-update assertions.

- [ ] **Step 2: Run database tests to verify the new cases fail**

Run the repository’s existing Supabase pgTAP command against the local linked/test database, after discovering the exact command with `supabase test --help`.

Expected: FAIL because devotion columns and the fourteen-argument RPC are absent.

- [ ] **Step 3: Generate the migration through Supabase CLI**

Run: `supabase migration new devotion_leaderboard`

Use the generated filename. Add non-null, non-negative columns/defaults and four descending metric indexes. Implement a guarded private fourteen-argument submit function, the new public invoker wrapper, and a preserved legacy wrapper that supplies the caller’s stored devotion values. Extend `read_board` allowlist and value expression. Revoke default execute access and grant only `authenticated` as for existing functions.

- [ ] **Step 4: Run advisors and migration checks before cloud deployment**

Run `supabase db advisors --help`, then the discovered advisor command; fix any security findings caused by this migration. Run `supabase migration list --local` and inspect the generated migration diff. Confirm no direct public-table mutation grant was introduced.

- [ ] **Step 5: Run pgTAP tests to verify they pass**

Run the same discovered Supabase test command.

Expected: PASS, proving metric validation, compatibility, board query, RLS, and RPC-only writes.

- [ ] **Step 6: Apply to the linked production project and perform an authenticated smoke query**

Apply the reviewed migration using the project’s authorized Supabase workflow. With an anonymous authenticated session and the publishable key, submit a zero-valued valid fourteen-aggregate snapshot and query `get_leaderboard('devotion_days', 50)`. Confirm HTTP success; verify an unsupported static metric still returns the expected validation error. Never print credentials.

- [ ] **Step 7: Commit the migration and tests**

```bash
git add -- supabase/tests/leaderboard.sql
git commit -m "feat: add devotion leaderboard aggregates"
```

Before committing, stage the single migration file generated in Step 3 by its exact generated path; do not use a wildcard that could include another person’s migration.

### Task 8: Execute regression verification, review, and release handoff

**Files:**
- Modify only files required by fixes discovered in verification.
- Test: all Flutter tests and existing Supabase migration tests.

**Interfaces:**
- Consumes every interface produced by Tasks 1–7.
- Produces an evidence-backed summary of local tests, database tests, authenticated cloud query, and build/release state.

- [ ] **Step 1: Run formatting and static analysis**

Run: `dart format --set-exit-if-changed lib test && flutter analyze`

Expected: no formatting changes required and no analyzer errors.

- [ ] **Step 2: Run the complete Flutter suite**

Run: `flutter test`

Expected: PASS; investigate and fix every failure before proceeding.

- [ ] **Step 3: Review the complete diff against the approved spec**

Check each explicit requirement: foreground-only timing; strict threshold/note completion; one completion per day; all four local stats; today state; reminder count; exact leaderboard ordering/names; cloud fields, RLS, and caching. Confirm no user-owned unrelated files are staged.

- [ ] **Step 4: Commit any verification fixes separately**

```bash
git status --short
```

If verification requires a fix, stage each displayed fix file by its literal path and use commit message `fix: complete devotion learning verification`; otherwise make no extra commit.

- [ ] **Step 5: Request fresh whole-branch review and report release readiness**

Provide the reviewer the approved spec, this plan, migration diff, and test evidence. Address actionable review findings, rerun affected tests, then report the commit range and whether an Android/iOS release build is ready for the user’s explicit release decision.

# Leaderboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Supabase-backed, low-request leaderboard to “我的”, with seven changing learning metrics, offline operation, and a Cloudflare-replaceable gateway.

**Architecture:** SQLite remains the source of truth. A `LeaderboardSyncController` builds one aggregate snapshot, persists dirty/cache state in existing app settings, and depends only on `LeaderboardGateway`; Supabase is the first implementation. The page uses cached data first and exposes background/manual refresh.

**Tech Stack:** Flutter/Dart, Riverpod, SQLite settings, `supabase_flutter`, `device_info_plus`, Supabase anonymous auth, Postgres/RLS/RPC.

**Spec:** `docs/superpowers/specs/2026-10-03-leaderboard-design.md`

## Global Constraints

- Rank only total recitations, unique recited verses, maximum day streak, badge awards, total recitation seconds, current day streak, and quiz accuracy.
- Never rank registration time, account age, or creation time.
- Upload one aggregate snapshot after a 15-minute debounce; retain dirty state across restarts and failures.
- Cache each metric for 5 minutes and render cached results before network refresh.
- Use `profile_name` when present; otherwise use `device model · random six-character installation alias` without IMEI, serial number, MAC address, or hardware IDs.
- Read Supabase URL and publishable key from `--dart-define`; never commit credentials or service-role keys.
- Enable RLS and expose constrained RPCs only. A missing configuration, offline state, or anonymous-auth failure must not block local learning.

## Review Focus

- Blank Supabase configuration renders local stats and no exception.
- Repeated quiz answers only schedule a deferred aggregate upload.
- Current day streak may decrease; cumulative metrics may not.
- A user with zero answered quiz questions is unranked for accuracy.
- Cached rows remain visible when refresh or anonymous sign-in fails.

---

### Task 1: Define the leaderboard domain and aggregate builder

**Files:**

- Create: `lib/src/features/leaderboard/domain/leaderboard_models.dart`
- Create: `lib/src/features/leaderboard/domain/leaderboard_gateway.dart`
- Create: `lib/src/features/leaderboard/application/leaderboard_snapshot_builder.dart`
- Create: `test/leaderboard/leaderboard_snapshot_builder_test.dart`

**Interfaces:**

- Consumes: `RecitationSummary`, `LearningStats`, `QuizSummary`, and `Iterable<AchievementProgress>`.
- Produces: seven-value `LeaderboardMetric`, `LeaderboardSnapshot`, `LeaderboardEntry`, `LeaderboardViewData`, and `LeaderboardGateway`.

- [ ] **Step 1: Write failing aggregate-builder tests**

```dart
test('builds all seven leaderboard values from local aggregates', () {
  final snapshot = buildLeaderboardSnapshot(/* fixed aggregates */);
  expect(snapshot.totalSessions, 4);
  expect(snapshot.uniqueVerses, 12);
  expect(snapshot.badgeAwards, 3);
  expect(snapshot.quizAnswered, 10);
  expect(snapshot.quizCorrect, 8);
});

test('excludes locked badges and retains repeatable award counts', () {
  expect(snapshot.badgeAwards, 3);
});
```

- [ ] **Step 2: Run the tests to verify RED**

Run: `flutter test test/leaderboard/leaderboard_snapshot_builder_test.dart`

Expected: FAIL because the types and builder do not exist.

- [ ] **Step 3: Implement the domain and builder**

Define exactly these metrics: `totalSessions`, `uniqueVerses`, `maxDayStreak`, `badgeAwards`, `totalRecitationSeconds`, `currentDayStreak`, and `quizAccuracy`. Store quiz numerator/denominator in the snapshot rather than a floating-point ratio. Sum `awardCount` only where `unlockedAt != null`.

- [ ] **Step 4: Run the tests to verify GREEN**

Run: `flutter test test/leaderboard/leaderboard_snapshot_builder_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/leaderboard/domain lib/src/features/leaderboard/application/leaderboard_snapshot_builder.dart test/leaderboard/leaderboard_snapshot_builder_test.dart
git commit -m "feat: define leaderboard aggregates"
```

### Task 2: Add Supabase configuration and privacy-safe device aliases

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/src/features/leaderboard/data/leaderboard_config.dart`
- Create: `lib/src/features/leaderboard/data/device_alias_source.dart`
- Create: `test/leaderboard/device_alias_source_test.dart`
- Modify: `README.md`

**Interfaces:**

- Consumes: compile-time `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, an injected device-model reader, and existing app settings.
- Produces: `LeaderboardConfig.isConfigured` and `DeviceAliasSource.loadOrCreate(repository)`.

- [ ] **Step 1: Write failing configuration and alias tests**

```dart
test('is unavailable when either Supabase define is blank', () {
  expect(LeaderboardConfig('', '').isConfigured, isFalse);
});

test('reuses a generated alias and formats a safe device fallback', () async {
  expect(await source.loadOrCreate(repository), 'Pixel 8 · A1B2C3');
});
```

- [ ] **Step 2: Run the tests to verify RED**

Run: `flutter test test/leaderboard/device_alias_source_test.dart`

Expected: FAIL because the configuration and alias source do not exist.

- [ ] **Step 3: Implement configuration and aliasing**

Add pinned dependencies `supabase_flutter: 2.18.0` and `device_info_plus: 13.3.0`; update the lockfile. Read only manufacturer/model fields, sanitize and bound the string, generate six uppercase base32 characters with secure randomness once, and store the alias in existing app settings. Use `本机设备` when a model is unavailable. Document required build defines with placeholders only.

- [ ] **Step 4: Run the tests to verify GREEN**

Run: `flutter test test/leaderboard/device_alias_source_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock README.md lib/src/features/leaderboard/data test/leaderboard/device_alias_source_test.dart
git commit -m "feat: configure leaderboard identity"
```

### Task 3: Create the secure Supabase database contract

**Files:**

- Create: `supabase/migrations/<generated>_leaderboard.sql` using `supabase migration new leaderboard`
- Create: `supabase/tests/leaderboard.sql`
- Modify: `README.md`

**Interfaces:**

- Consumes: authenticated anonymous users and `LeaderboardSnapshot`.
- Produces: `public.submit_leaderboard_snapshot(...)` and `public.get_leaderboard(metric text, limit_count integer)` for the gateway.

- [ ] **Step 1: Write failing database assertions**

```sql
-- user A cannot update user B
-- unsupported metrics are rejected
-- lower total_sessions is rejected
-- lower current_day_streak is accepted
-- quiz_answered = 0 is excluded from quiz_accuracy
```

- [ ] **Step 2: Run database tests to verify RED**

Run: `supabase test db`

Expected: FAIL because the tables and RPCs do not exist.

- [ ] **Step 3: Create the migration and RLS rules**

Create `leaderboard_profile` and `leaderboard_score`, keyed by `auth.users.id`. Score fields are total sessions, unique verses, maximum day streak, badge awards, total recitation seconds, current day streak, quiz answered, quiz correct, and update time. Add ranking indexes, enable RLS, revoke default client grants, and grant only required authenticated access.

Implement submit with `auth.uid()` ownership, non-negative validation, and non-decreasing guards for the five cumulative values; allow current streak and quiz ratio inputs to change. Implement read with a seven-value allowlist, deterministic ordering, `row_number()`, top 50 plus caller rank, and zero-answer accuracy exclusion. Revoke `PUBLIC` execution and grant `authenticated`; use explicit schema references and a safe search path. Document enabling Anonymous Sign-ins, Data API exposure, CAPTCHA, and rate limiting.

- [ ] **Step 4: Run database tests and advisors to verify GREEN**

Run: `supabase test db && supabase db advisors`

Expected: PASS with no unresolved security advisory introduced by leaderboard tables/functions.

- [ ] **Step 5: Commit**

```bash
git add supabase README.md
git commit -m "feat: add secure leaderboard database contract"
```

### Task 4: Implement gateway, durable caching, and throttle control

**Files:**

- Create: `lib/src/features/leaderboard/data/supabase_leaderboard_gateway.dart`
- Create: `lib/src/features/leaderboard/data/offline_leaderboard_gateway.dart`
- Create: `lib/src/features/leaderboard/application/leaderboard_sync_controller.dart`
- Create: `lib/src/features/leaderboard/application/leaderboard_providers.dart`
- Create: `test/leaderboard/leaderboard_sync_controller_test.dart`
- Create: `test/leaderboard/supabase_leaderboard_gateway_test.dart`

**Interfaces:**

- Consumes: `LeaderboardGateway`, app settings, snapshot builder, clock, and Task 2 configuration.
- Produces: `markDirty()`, `syncIfDue()`, `refresh(metric)`, and Riverpod providers.

- [ ] **Step 1: Write failing controller and gateway contract tests**

```dart
test('coalesces changes into one upload after fifteen minutes', () async {
  await controller.markDirty();
  await controller.markDirty();
  await clock.advance(const Duration(minutes: 15));
  await controller.syncIfDue();
  expect(gateway.uploads, hasLength(1));
});

test('returns cache on refresh failure and keeps the snapshot dirty', () async {
  expect((await controller.refresh(LeaderboardMetric.totalSessions)).entries, isNotEmpty);
  expect(await controller.isDirty(), isTrue);
});

test('does not call Supabase with missing configuration', () async {
  expect(gateway.calls, isEmpty);
});
```

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/leaderboard/leaderboard_sync_controller_test.dart test/leaderboard/supabase_leaderboard_gateway_test.dart`

Expected: FAIL because the controller and gateways do not exist.

- [ ] **Step 3: Implement the controller and gateways**

Initialize Supabase only when both defines are present. The Supabase gateway signs in anonymously only when the session is missing, resolves user name from `profile_name` or the saved device alias, and invokes the two RPCs. Persist dirty time, last success, alias, and per-metric JSON cache in settings. Upload at most once per 15 minutes except explicit user refresh; retain dirty state on failure. Return cache younger than 5 minutes without RPC. Offline gateway returns local summary/empty rows and never throws.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `flutter test test/leaderboard/leaderboard_sync_controller_test.dart test/leaderboard/supabase_leaderboard_gateway_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/leaderboard/data lib/src/features/leaderboard/application test/leaderboard
git commit -m "feat: add cached leaderboard synchronization"
```

### Task 5: Wire local changes and app lifecycle synchronization

**Files:**

- Modify: `lib/src/features/recitation/presentation/recitation_practice_screen.dart`
- Modify: `lib/src/features/quiz/presentation/quiz_practice_screen.dart`
- Modify: `lib/src/features/plans/presentation/plans_screen.dart`
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Modify: `lib/src/app/app.dart`
- Create: `test/leaderboard/leaderboard_change_wiring_test.dart`

**Interfaces:**

- Consumes: Task 4 controller `markDirty()` and `syncIfDue()`.
- Produces: a dirty snapshot after recitation, quiz answer, badge-earning plan completion, and profile-name change; launch/resume best-effort sync.

- [ ] **Step 1: Write failing mutation-boundary tests**

```dart
testWidgets('finishing recitation marks leaderboard dirty', (tester) async {
  // complete real local flow
  expect(fakeLeaderboard.dirtyMarks, 1);
});

testWidgets('saving a profile name marks leaderboard dirty', (tester) async {
  // save profile_name through My
  expect(fakeLeaderboard.dirtyMarks, 1);
});
```

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/leaderboard/leaderboard_change_wiring_test.dart`

Expected: FAIL because existing mutations do not notify the controller.

- [ ] **Step 3: Add narrow notifications**

After successful recitation save, quiz completion, plan completion that may award a badge, and profile-name save, call `markDirty()` without awaiting network. On launch/resume call `syncIfDue()` using the existing best-effort pattern so failures cannot delay startup.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `flutter test test/leaderboard/leaderboard_change_wiring_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/app/app.dart lib/src/features/recitation lib/src/features/quiz lib/src/features/plans lib/src/features/statistics test/leaderboard/leaderboard_change_wiring_test.dart
git commit -m "feat: schedule leaderboard syncs from learning changes"
```

### Task 6: Add “我的” entry and the leaderboard page

**Files:**

- Create: `lib/src/features/leaderboard/presentation/leaderboard_screen.dart`
- Modify: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Modify: `lib/src/app/router.dart`
- Modify: `test/statistics/statistics_screen_test.dart`
- Create: `test/leaderboard/leaderboard_screen_test.dart`
- Modify: `test/app/app_navigation_test.dart`

**Interfaces:**

- Consumes: Task 4 provider and Task 1 metrics.
- Produces: `/statistics/leaderboard`, key `leaderboard-open`, and cached/loading/error/empty rendering.

- [ ] **Step 1: Write failing widget and navigation tests**

```dart
testWidgets('My exposes the leaderboard entry', (tester) async {
  expect(find.byKey(const Key('leaderboard-open')), findsOneWidget);
});

testWidgets('switches to quiz accuracy and highlights current user', (tester) async {
  await tester.tap(find.byKey(const Key('leaderboard-metric-quizAccuracy')));
  expect(find.byKey(const Key('leaderboard-current-user')), findsOneWidget);
});

testWidgets('keeps cached rows after refresh failure', (tester) async {
  expect(find.text('暂无法更新'), findsOneWidget);
});
```

- [ ] **Step 2: Run tests to verify RED**

Run: `flutter test test/statistics/statistics_screen_test.dart test/leaderboard/leaderboard_screen_test.dart test/app/app_navigation_test.dart`

Expected: FAIL because the route, entry, and screen do not exist.

- [ ] **Step 3: Implement route and UI**

Add a My-page `ListTile` keyed `leaderboard-open` and route `/statistics/leaderboard`. Build a scrollable seven-metric selector keyed `leaderboard-metric-<metricName>`, ranking rows, current-user highlight, local summary, pull-to-refresh, cached timestamp, offline notice, and empty state. Format duration as hours/minutes and accuracy as percent. Keep the page usable via the offline gateway.

- [ ] **Step 4: Run tests to verify GREEN**

Run: `flutter test test/statistics/statistics_screen_test.dart test/leaderboard/leaderboard_screen_test.dart test/app/app_navigation_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/leaderboard/presentation lib/src/features/statistics/presentation/statistics_screen.dart lib/src/app/router.dart test/statistics test/leaderboard test/app/app_navigation_test.dart
git commit -m "feat: add leaderboard to My"
```

### Task 7: Verify end-to-end behavior and deployment documentation

**Files:**

- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-10-03-leaderboard-design.md` only if verification reveals a design correction.

**Interfaces:**

- Consumes: completed Tasks 1–6 and a configured Supabase project.
- Produces: reproducible database, Flutter, and manual verification instructions.

- [ ] **Step 1: Add production setup and verification instructions**

Document anonymous-auth dashboard setup, migration deployment, required dart defines, and the 15-minute upload / 5-minute cache behavior.

- [ ] **Step 2: Run automated checks**

Run: `flutter analyze && flutter test && supabase test db && supabase db advisors`

Expected: Flutter tests and database tests PASS; advisors contain no unresolved leaderboard finding.

- [ ] **Step 3: Perform a configured smoke test**

Build with local non-secret defines, complete a recitation and quiz, confirm neither sends an immediate upload, advance or inject a clock past 15 minutes, confirm one snapshot upload, and open the page twice to confirm the second open reuses its 5-minute cache.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/specs/2026-10-03-leaderboard-design.md
git commit -m "docs: verify leaderboard deployment"
```

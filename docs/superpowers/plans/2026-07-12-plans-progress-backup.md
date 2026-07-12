# Plans, Progress, Statistics, and Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist recitation attempts, calculate mastery and reviews, generate and repair memorization plans, show today/statistics views, schedule local reminders, and provide password-encrypted full backup and transactional restore.

**Architecture:** A separate Drift `user.sqlite` stores all mutable data and references immutable scripture packs only through stable `VerseKey` values. Pure Dart policies implement plan generation, catch-up, mastery, and reminder reconciliation. Backup uses a versioned binary envelope around an encrypted ZIP and restores through staging, validation, and an atomic database swap.

**Tech Stack:** Flutter 3.44.4, Dart 3.12.2, drift 2.34.1, drift_flutter 0.3.0, drift_dev 2.34.3, sqlite3 3.3.4, flutter_local_notifications 22.0.1, timezone 0.11.1, flutter_timezone 5.1.0, uuid 4.5.3, cryptography 2.9.0, archive 4.0.9, file_picker 11.0.2, Riverpod 3.3.2.

## Global Constraints

- Complete the foundation and offline-recitation plans first.
- Keep `user.sqlite` separate from read-only `scripture.sqlite` packs.
- Every persisted entity uses UUID or stable scripture keys; never expose SQLite row IDs across backup boundaries.
- Store instants as UTC milliseconds and plan/attempt local dates as integer calendar days, not UTC midnights. Persist the attempt-time IANA zone ID and offset so travel or later time-zone changes cannot rewrite history.
- Review intervals are exactly 1, 3, 7, 14, and 30 days.
- Missed work uses free buffer days first, then future unlocked study days; never change a locked task or silently extend a deadline.
- Notifications are local only, at most 32 rolling one-shot reminders, so behavior fits iOS and Windows limits.
- Backup v1 is full replacement, never merge. Any failure before the durable atomic-replace commit point leaves the old live database unchanged; after that point the operation is committed and recovery completes the new database's post-commit work instead of reporting an ordinary failure.
- Backup cryptography is Argon2id + XChaCha20-Poly1305 with exact parameters below.
- Raw recordings are excluded unless the user explicitly requests them.
- Every task uses a fake clock where dates matter, follows TDD, and ends with a commit.

---

## File Structure

```text
lib/src/core/database/app_database.dart
lib/src/core/database/migrations.dart
lib/src/core/database/tables/*.dart
lib/src/core/time/app_clock.dart
lib/src/core/time/local_date.dart
lib/src/features/progress/{domain,application,data}/*.dart
lib/src/features/mastery/domain/*.dart
lib/src/features/plans/{domain,application,data,presentation}/*.dart
lib/src/features/today/{application,presentation}/*.dart
lib/src/features/reminders/{domain,application,data}/*.dart
lib/src/features/statistics/{domain,data,presentation}/*.dart
lib/src/features/backup/{domain,application,data,presentation}/*.dart
android/app/src/main/kotlin/app/biblerecite/BackupDocumentPlugin.kt
ios/Runner/BackupDocumentPlugin.swift
drift_schemas/schema_v1.json
test/database/**
test/progress/**
test/plans/**
test/reminders/**
test/statistics/**
test/backup/**
integration_test/backup_restore_crash_recovery_test.dart
```

## Stable Interfaces

```dart
abstract interface class AppClock {
  DateTime nowUtc();
  LocalDate today();
}

abstract interface class PracticeProgressStore {
  Future<AttemptCommitResult> commit(AttemptCommit command);
  Future<VerseMastery?> findMastery(MasteryKey key);
  Stream<List<ReviewQueueItem>> watchDueReviews(LocalDate through);
}

abstract interface class PlanRepository {
  Future<Plan?> find(String id);
  Stream<List<PlanSummary>> watchPlans();
  Stream<List<PlanTask>> watchTasks({required LocalDate from, required LocalDate through});
  Future<void> create(Plan plan);
  Future<void> apply(PlanMutation mutation, {required int expectedRevision});
}

abstract interface class ReminderGateway {
  Future<NotificationPermissionState> permissionState();
  Future<NotificationPermissionState> requestPermission();
  Future<Set<int>> pendingIds();
  Future<void> scheduleOneShot(ReminderSpec reminder);
  Future<void> cancel(int id);
  Stream<ReminderActivation> get activations;
}

abstract interface class BackupFileGateway {
  Future<BackupImportHandle?> chooseImport();
  Future<BackupExportHandle?> chooseExport({required String suggestedFileName});
}

abstract interface class BackupEnvelopeCodec {
  Future<BackupManifest> encrypt({required BackupPayloadSource payload, required String password, required BackupExportHandle destination});
  Future<VerifiedBackupPayload> decrypt({required BackupImportHandle source, required String password, required Directory stagingDirectory});
}

abstract interface class DatabaseRestoreCoordinator {
  Future<RestoreResult> restore(VerifiedBackupPayload payload);
  Future<void> recoverInterruptedRestore();
}
```

## Task 1: Create the versioned Drift user database

**Files:**
- Create: `lib/src/core/time/local_date.dart`
- Create: `lib/src/core/time/app_clock.dart`
- Create: `lib/src/core/database/app_database.dart`
- Create: `lib/src/core/database/checked_database_opener.dart`
- Create: `lib/src/core/database/process_instance_lease.dart`
- Create: `lib/src/core/database/migrations.dart`
- Create: `lib/src/core/database/tables/plans.dart`
- Create: `lib/src/core/database/tables/plan_tasks.dart`
- Create: `lib/src/core/database/tables/plan_task_ranges.dart`
- Create: `lib/src/core/database/tables/plan_task_verses.dart`
- Create: `lib/src/core/database/tables/practice_attempts.dart`
- Create: `lib/src/core/database/tables/practice_attempt_ranges.dart`
- Create: `lib/src/core/database/tables/practice_attempt_verses.dart`
- Create: `lib/src/core/database/tables/verse_mastery.dart`
- Create: `lib/src/core/database/tables/review_queue_items.dart`
- Create: `lib/src/core/database/tables/reminder_registrations.dart`
- Create: `lib/src/core/database/tables/app_settings.dart`
- Create: `lib/src/core/database/tables/saved_recordings.dart`
- Create: `lib/src/core/database/tables/scripture_revision_requirements.dart`
- Generate: `lib/src/core/database/app_database.g.dart`
- Generate: `drift_schemas/schema_v1.json`
- Test: `test/database/app_database_test.dart`
- Test: `test/database/migrations_test.dart`

**Interfaces:**
- Produces: `CheckedDatabaseOpener.openDefault()`, `openPath(String)`, and injectable `AppDatabase(QueryExecutor)`.
- Consumes: stable `VerseKey` plus `TranslationInfo.packId`, `versificationId`, and `semanticSha256` from the foundation plan.

- [ ] **Step 1: Add exact Drift dependencies**

```powershell
.\.toolchains\flutter\bin\flutter.bat pub add drift:2.34.1 drift_flutter:0.3.0 sqlite3:3.3.4 flutter_local_notifications:22.0.1 timezone:0.11.1 flutter_timezone:5.1.0 file_picker:11.0.2 uuid:4.5.3
.\.toolchains\flutter\bin\flutter.bat pub add --dev drift_dev:2.34.3 build_runner:2.15.1
```

- [ ] **Step 2: Write failing schema and migration tests**

```dart
test('enables foreign keys and starts at schema version one', () async {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  expect(database.schemaVersion, 1);
  expect((await database.customSelect('PRAGMA foreign_keys').getSingle()).data['foreign_keys'], 1);
});

test('rolls back a failed migration and leaves the old database readable', () async {
  final fixture = await createRealSchemaV1Fixture();
  await expectLater(openWithInjectedMigrationFailure(fixture), throwsA(isA<DatabaseMigrationFailure>()));
  expect(await reopenSchemaV1Fixture(fixture), isNotNull);
});

test('rejects a database from a newer schema without changing it', () async {
  final fixture = await createFutureSchemaFixture(userVersion: 99);
  final before = await sha256File(fixture);
  await expectLater(CheckedDatabaseOpener().openPath(fixture.path), throwsA(isA<FutureDatabaseSchema>()));
  expect(await sha256File(fixture), before);
});
```

- [ ] **Step 3: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/database/app_database_test.dart test/database/migrations_test.dart`

Expected: FAIL because database classes are missing.

- [ ] **Step 4: Implement schema v1**

Use RFC 9562 UUIDv7 text primary keys generated by `uuid 4.5.3`. `PracticeAttempts` stores session, translation ID, pack ID, versification ID, semantic content SHA-256, UTC timestamp, `attemptedLocalDate`, attempt-time IANA zone ID/offset, mode, outcome, mastery, duration, hints, corrections, and unresolved-error count. Ordered `PracticeAttemptRanges` preserve the exact `PassageSelection`; child verse rows store exact `VerseKey` and serialized findings. Stable `VerseKey` values do not contain a translation, while `VerseMastery` deliberately uses composite key `(translationId, semanticSha256, canonId, bookId, chapter, verse)` so mastery remains wording-specific and a replacement source cannot silently inherit it. `PlanTasks` has the same scripture-revision identity plus `localDate`, `kind`, `status`, `position`, and `locked`; ordered `PlanTaskRanges` plus task-verses preserve discrete selection boundaries and stable keys. `SavedRecordings` stores attempt UUID, 64-character lowercase content hash, byte size, MIME type, and availability only; it has no path column.

Define these database constraints explicitly:

- plan/task/attempt range and verse child rows use foreign keys with `ON DELETE CASCADE`; an attempt's optional task reference uses `ON DELETE SET NULL`;
- `PlanTasks` is unique on `(planId, localDate, position)` and checks revision, position, date, kind, and status values;
- task/attempt range rows are unique on `(ownerId, ordinal)`, use row checks for same-canon/same-book ordered endpoints, and use insert/update triggers to reject overlap or noncanonical ordering within an owner; verse members are unique on `(ownerId, ordinal)` and on `(ownerId, translationId, canonId, bookId, chapter, verse)`;
- `VerseMasteries` has the full translation plus `VerseKey` composite primary key and checks score 0–100 and the interval index;
- at most one active review item exists per mastery key and review kind; due-date, task-date, attempt-time, and plan-status indexes support Today/statistics;
- `ReminderRegistrations` is unique on both task UUID and notification integer ID;
- `SavedRecordings` references attempts with cascade, requires a 64-character lowercase content hash, nonnegative size, and a valid availability enum; physical paths are derived from the hash rather than persisted.
- `ScriptureRevisionRequirements` is keyed by translation ID plus semantic SHA-256 and retains pack/versification IDs so restored history is never silently rebound to changed wording.

Enable `PRAGMA foreign_keys=ON`, WAL, and a busy timeout before normal work. Reject `user_version` above the supported schema before opening Drift. Real upgrades use generated `stepByStep` or explicit `onUpgrade` migrations within a transaction and a real previous-schema fixture; do not infer migration safety from a no-op v1 strategy.

```dart
@DriftDatabase(tables: [Plans, PlanTasks, PlanTaskRanges, PlanTaskVerses, PracticeAttempts, PracticeAttemptRanges, PracticeAttemptVerses, VerseMasteries, ReviewQueueItems, ReminderRegistrations, AppSettings, SavedRecordings, ScriptureRevisionRequirements])
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  @override int get schemaVersion => 1;
  @override MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: migrateSchema,
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );
}
```

Application bootstrap acquires `ProcessInstanceLease` before any database or reminder gateway is opened and holds it for the process lifetime. On Windows and macOS this is an exclusive OS-backed lock on a sibling lock file, making the desktop app single-instance; acquisition failure exits before any database, recording, notification, staging, or marker mutation. Mobile keeps the same bootstrap ordering while relying on its single foreground application process. Restore and startup recovery require proof that the caller owns this lease in addition to their in-process maintenance lease.

Under the held process lease, `CheckedDatabaseOpener` resolves the default/path file. If it does not exist, it passes the path directly to Drift for first-run creation. If it exists, it opens it read-only with `sqlite3`, reads `PRAGMA user_version`, closes the probe, and rejects `from > 1` without mutation; it then constructs `AppDatabase(NativeDatabase(file))` while still holding the lease, eliminating the probe/open TOCTOU window. Both default and explicit-path production openings must use this one gateway; do not retain a direct named constructor that bypasses preflight.

In `migrations.dart`, `migrateSchema(Migrator m, int from, int to)` first rejects `from > 1 || to > 1`, returns only when `from == to`, and otherwise throws `DatabaseMigrationFailure('No supported migration path from $from to $to')`. When schema v2 is introduced, replace that rejection with Drift's generated `stepByStep` migration and retain the committed schema-v1 fixture.

- [ ] **Step 5: Generate code/schema and run tests**

```powershell
.\.toolchains\flutter\bin\dart.bat run build_runner build --delete-conflicting-outputs
.\.toolchains\flutter\bin\dart.bat run drift_dev schema dump lib/src/core/database/app_database.dart drift_schemas/
.\.toolchains\flutter\bin\flutter.bat test test/database
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: tests PASS and generated files have no unstaged regeneration diff after a second run.

Add a two-connection concurrency test proving duplicate `attemptId` commits produce one attempt, one verse-row set, and one mastery transition. Add negative schema tests for duplicate task positions, duplicate active reviews, orphan verse rows, invalid mastery values, invalid recording hashes/sizes/MIME/availability, and prove every hash-derived recording path remains inside `recordings/blobs/`. Add a first-run test proving a missing database is created. The process-level restore contention test is completed in Task 9.

- [ ] **Step 6: Commit**

```powershell
git add pubspec.yaml pubspec.lock lib/src/core drift_schemas test/database
git commit -m "feat: add versioned local user database"
```

## Task 2: Persist attempts and update mastery atomically

**Files:**
- Create: `lib/src/features/progress/domain/progress_models.dart`
- Create: `lib/src/features/progress/domain/practice_progress_store.dart`
- Create: `lib/src/features/progress/application/record_practice_attempt.dart`
- Create: `lib/src/features/progress/data/drift_practice_progress_store.dart`
- Create: `lib/src/features/mastery/domain/mastery_policy.dart`
- Create: `lib/src/features/mastery/domain/review_interval_policy.dart`
- Test: `test/progress/record_practice_attempt_test.dart`
- Test: `test/progress/mastery_policy_test.dart`

**Interfaces:**
- Produces: `RecordPracticeAttempt.call(CompletedRecitation, AttemptContext)` and due review rows.
- Consumes: `CompletedRecitation` from the recitation plan, including its exact scripture revision, `PassageSelection`, typed hints/findings, and optional opted-in `RetainedRecordingDraft`.

- [ ] **Step 1: Write interval and rollback tests**

```dart
test('accurate stable passes advance through 1, 3, 7, 14, 30 days', () {
  var mastery = VerseMastery.initial(fixtureKey);
  final intervals = <int>[];
  var attemptedOn = LocalDate(2026, 7, 12);
  for (var i = 0; i < 5; i++) {
    mastery = policy.evaluate(previous: mastery, evidence: accurateEvidence, attemptedOn: attemptedOn);
    intervals.add(mastery.intervalDays);
    attemptedOn = mastery.dueOn;
  }
  expect(intervals, [1, 3, 7, 14, 30]);
});

test('an accurate review before due date records evidence without advancing', () {
  final previous = VerseMastery.initial(fixtureKey).copyWith(intervalDays: 7, dueOn: LocalDate(2026, 7, 19));
  final result = policy.evaluate(previous: previous, evidence: accurateEvidence, attemptedOn: LocalDate(2026, 7, 15));
  expect(result.intervalDays, 7);
  expect(result.dueOn, LocalDate(2026, 7, 19));
});

test('attempt, mastery, review, and plan task roll back together', () async {
  final store = storeWithFailpoint(AttemptCommitFailpoint.afterMastery);
  await expectLater(store.commit(fixtureCommand), throwsA(isA<InjectedCommitFailure>()));
  expect(await store.countAllAttemptArtifacts(), 0);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/progress/record_practice_attempt_test.dart test/progress/mastery_policy_test.dart`

Expected: FAIL for missing policies/stores.

- [ ] **Step 3: Implement deterministic mastery and one transaction**

An accurate stable pass advances one step only when attempted on or after `dueOn`; a manual early review records evidence but keeps both the interval and due date. Pass-with-review stays at the same step unless current interval is zero, where it becomes one day. Failure sets interval to one day and queues `failedRetry`. Manual early review never completes a plan task. `RecordPracticeAttempt` is the sole mapper from `CompletedRecitation` plus `AttemptContext` (attempt UUIDv7, optional task ID, UTC/local time and zone) into the canonical persistence command; there is no separate completion DTO. `DriftPracticeProgressStore.commit` inserts the attempt, ordered selection ranges, per-verse results, mastery, queue, and task completion in one transaction. If an opted-in recording draft exists, verify its hash/size/MIME, flush and atomically install the content-addressed blob before the transaction, then insert its metadata; a failed transaction may leave only an unreferenced blob for later garbage collection. Store a canonical SHA-256 command digest with the attempt: a repeated `attemptId` returns the original result only when the digest matches; a different payload returns `IdempotencyConflict`. The two-connection test must race identical and conflicting commands.

- [ ] **Step 4: Run focused and full tests**

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/progress
.\.toolchains\flutter\bin\flutter.bat test
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/progress lib/src/features/mastery test/progress
git commit -m "feat: persist attempts and schedule reviews atomically"
```

## Task 3: Generate balanced automatic plans

**Files:**
- Create: `lib/src/features/plans/domain/plan_models.dart`
- Create: `lib/src/features/plans/domain/plan_generator.dart`
- Test: `test/plans/plan_generator_test.dart`

**Interfaces:**
- Produces: `PlanGenerator.generate(...) -> PlanGenerationResult`.
- Consumes: selected `PassageSelection`, scripture token counts, mastery difficulty.

- [ ] **Step 1: Write scheduling tests**

```dart
test('balances by work weight and leaves rest/buffer days empty', () {
  final result = generator.generate(input: fixtureThirtyDayInput, workItems: weightedPhilippians);
  expect(result.tasks.where((task) => task.date.weekday == DateTime.sunday), isEmpty);
  expect(result.bufferDates.length, 2);
  final weights = result.tasks.map((task) => task.weightUnits).toList();
  expect(weights.reduce(max) - weights.reduce(min), lessThanOrEqualTo(weightedPhilippians.maxSingleItemWeightUnits));
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/plans/plan_generator_test.dart`

Expected: FAIL for missing generator.

- [ ] **Step 3: Implement deterministic weighted allocation**

```dart
final class PassageWorkItem {
  const PassageWorkItem({required this.range, required this.tokenCount, required this.difficultyBasisPoints});
  final PassageRange range;
  final int tokenCount;
  final int difficultyBasisPoints; // clamped 0..10000
  int get weightUnits => tokenCount * (10000 + difficultyBasisPoints.clamp(0, 10000));
}
```

Expand every range in `PassageSelection.ranges` into work items in canonical selection order, preserving discrete gaps as hard boundaries. Quantize historical difficulty into integer basis points before generation; no floating-point value enters allocation or serialized plan JSON. Generate eligible dates, reserve explicitly requested buffer days from the end, and partition ordered work items into exactly `min(workItemCount, eligibleDayCount)` nonempty contiguous groups, leaving remaining eligible days empty at the end. A group may contain multiple range fragments but must never invent verses across a discrete gap. Integer-binary-search the inclusive range `[max(itemWeight), sum(itemWeight)]`; at each midpoint greedily take the longest prefix whose weight is within the cap while reserving at least one item for each remaining required group. Equal choices always choose the longest earlier prefix. Never move a later verse before an earlier verse because another day is lighter. Add the regression `[1, 10, 1]` over two study days and require `[1,10] | [1]` under that tie-break, never `[1,1] | [10]`. Persist the exact selection and algorithm version; identical input yields byte-identical plan JSON.

- [ ] **Step 4: Run tests and commit**

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/plans/plan_generator_test.dart
.\.toolchains\flutter\bin\flutter.bat analyze
git add lib/src/features/plans/domain test/plans/plan_generator_test.dart
git commit -m "feat: generate balanced memorization plans"
```

## Task 4: Support manual locks and catch-up proposals

**Files:**
- Create: `lib/src/features/plans/domain/plan_rescheduler.dart`
- Create: `lib/src/features/plans/domain/plan_mutation.dart`
- Create: `lib/src/features/plans/data/drift_plan_repository.dart`
- Test: `test/plans/plan_rescheduler_test.dart`
- Test: `test/plans/drift_plan_repository_test.dart`

**Interfaces:**
- Produces: optimistic-revision `PlanRepository.apply` and `CatchUpProposal`.
- Consumes: plans from Task 3.

- [ ] **Step 1: Write buffer, lock, and impossible-deadline tests**

```dart
test('moves the contiguous unfinished suffix through a buffer without reordering scripture', () {
  final proposal = rescheduler.propose(plan: orderedUnfinishedSuffixAndFridayBuffer, today: friday, missedTaskIds: {'monday'}, choice: CatchUpChoice.keepDeadline);
  expect(proposal.moves.map((move) => move.taskId), orderedUnfinishedSuffixTaskIds);
  expect(flattenVerseKeysByDateAndPosition(proposal.plan), originalOrderedVerseKeys);
  expect(proposal.changedLockedTaskIds, isEmpty);
});

test('cannot keep deadline when a completed task splits the suffix', () {
  final proposal = rescheduler.propose(plan: suffixSplitByCompletedTask, today: friday, missedTaskIds: {'monday'}, choice: CatchUpChoice.keepDeadline);
  expect(proposal.requiresDecision, isTrue);
  expect(proposal.moves, isEmpty);
});

test('returns choices instead of silently moving the deadline', () {
  final proposal = rescheduler.propose(plan: impossiblePlan, today: today, missedTaskIds: missed, choice: CatchUpChoice.requestOptions);
  expect(proposal.requiresDecision, isTrue);
  expect(proposal.options.map((option) => option.kind), containsAll([CatchUpOptionKind.extendDeadline, CatchUpOptionKind.increaseDailyLoad]));
});
```

- [ ] **Step 2: Run, implement, and verify**

Use future unlocked study days only and move a contiguous unfinished suffix so the flattened `(date, position)` VerseKey sequence remains unchanged. A completed or locked task that splits the suffix makes `keepDeadline` infeasible and returns explicit options. `PlanRepository.create` is insert-only and fails on an existing UUID. Every edit/reschedule of an existing plan uses `apply` with `WHERE revision = expectedRevision` and increments the revision in the same transaction; zero updated rows throws `PlanRevisionConflict`. Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/plans
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: PASS.

- [ ] **Step 3: Commit**

```powershell
git add lib/src/features/plans test/plans
git commit -m "feat: reschedule missed work without breaking locks"
```

## Task 5: Build Today and Plan editing flows

**Files:**
- Create: `lib/src/features/today/application/watch_today.dart`
- Create: `lib/src/features/today/presentation/today_screen.dart`
- Create: `lib/src/features/plans/presentation/plan_list_screen.dart`
- Create: `lib/src/features/plans/presentation/plan_editor_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/src/app/router.dart`
- Test: `test/plans/plan_editor_screen_test.dart`
- Test: `test/plans/today_screen_test.dart`

**Interfaces:**
- Produces approved Today and Plan UI.
- Consumes plan repository, due reviews, and recitation routes.

- [ ] **Step 1: Write widget tests for automatic/manual creation and catch-up choice**

```dart
testWidgets('creates a 30-day plan with rest and buffer days', (tester) async {
  await tester.pumpWidget(planEditorTestApp());
  await tester.enterText(find.byKey(const Key('duration-days')), '30');
  await tester.tap(find.text('周日休息'));
  await tester.enterText(find.byKey(const Key('buffer-days')), '2');
  await tester.tap(find.text('生成计划'));
  await tester.pumpAndSettle();
  expect(find.textContaining('30 天'), findsOneWidget);
});
```

- [ ] **Step 2: Run, implement, and verify**

Today merges new work, due reviews, and failed retries without duplicates. Plan editor supports automatic/manual mode, learning days, rest days, buffers, drag/move, split, merge, lock, pause, and catch-up decision. Add all Today/plan/reminder strings and placeholders to all three ARBs and run locale-key parity before widget tests. Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/plans
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: PASS with no overflow at mobile and desktop widths.

- [ ] **Step 3: Commit**

```powershell
git add lib/src/features/today lib/src/features/plans/presentation lib/l10n lib/src/app/router.dart test/plans
git commit -m "feat: add today and plan management flows"
```

## Task 6: Reconcile rolling local reminders

**Files:**
- Create: `lib/src/features/reminders/domain/reminder_gateway.dart`
- Create: `lib/src/features/reminders/application/reminder_coordinator.dart`
- Create: `lib/src/features/reminders/data/flutter_local_notifications_gateway.dart`
- Test: `test/reminders/reminder_coordinator_test.dart`

**Interfaces:**
- Produces: stable, idempotent 30-day reminder schedule.
- Consumes: plan/today queries.

- [ ] **Step 1: Write reconciliation-limit tests**

```dart
test('keeps at most 32 one-shot reminders and cancels stale IDs', () async {
  final gateway = FakeReminderGateway(pending: {101, 202, 999});
  final registrations = FakeReminderRegistrations({'current-task': 101, 'stale-task': 202});
  final result = await ReminderCoordinatorImpl(gateway: gateway, registrations: registrations, source: sourceWithFortyDays).reconcile(today: LocalDate(2026, 7, 12));
  expect(gateway.scheduled.length, lessThanOrEqualTo(32));
  expect(gateway.cancelled, contains(202));
  expect(gateway.cancelled, isNot(contains(999)));
  expect(result.pendingCount, lessThanOrEqualTo(32));
});
```

- [ ] **Step 2: Run, implement, and verify**

Initialize the `timezone 0.11.1` database once, resolve the device's IANA zone through `flutter_timezone 5.1.0`, and reschedule when the OS zone changes or the app next resumes. Use one-shot zoned notifications and payload `{"v":1,"route":"/today","taskId":"018f6f6c-7f66-7e13-8d1a-84f4d8be41c2"}` in the exact serialization test. Derive the initial ID by reading the first four SHA-256 bytes as unsigned big-endian, applying `& 0x7fffffff`, and changing zero to one. Resolve collisions by positive 31-bit linear probing with wrap from `0x7fffffff` to `1`, persisting the pair in `ReminderRegistrations`. Reconciliation may cancel only IDs in this app-owned table, never an arbitrary OS pending ID. Test ID stability across a fresh process, zero result, wraparound, and injected digest collision. Request permission only from a user action. Windows repeating APIs are forbidden. Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/reminders
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: PASS.

- [ ] **Step 3: Commit**

```powershell
git add lib/src/features/reminders test/reminders android ios macos windows
git commit -m "feat: schedule rolling local study reminders"
```

## Task 7: Add local progress statistics

**Files:**
- Create: `lib/src/features/statistics/domain/statistics_models.dart`
- Create: `lib/src/features/statistics/data/drift_statistics_repository.dart`
- Create: `lib/src/features/statistics/presentation/statistics_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/statistics/statistics_repository_test.dart`
- Test: `test/statistics/statistics_screen_test.dart`

**Interfaces:**
- Produces: history, streak, book progress, mastery distribution, due review, and trend queries.
- Consumes: user database only.

- [ ] **Step 1: Write timezone/streak and empty-state tests**

```dart
test('counts consecutive local dates across a UTC boundary', () async {
  final snapshot = await seededRepository(attemptsAtLocalDates(['2026-07-10', '2026-07-11', '2026-07-12'])).load(fixtureQuery);
  expect(snapshot.currentStreakDays, 3);
});
```

- [ ] **Step 2: Run, implement indexed SQL aggregates, and verify**

Do not add cache tables in v1. Streak queries use persisted `attemptedLocalDate`, never reinterpret UTC timestamps in the device's current zone. Query attempts and mastery through indexes, and show textual summaries alongside any bars/heatmaps. Add statistics labels, empty states, chart semantics, date/unit plural forms, and errors to all three ARBs. Add a regression that changes the current zone after seeding and proves the historical streak is unchanged. Run:

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/statistics
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: PASS.

- [ ] **Step 3: Commit**

```powershell
git add lib/src/features/statistics lib/l10n test/statistics
git commit -m "feat: report local memorization progress"
```

## Task 8: Encode and export a versioned encrypted backup

**Files:**
- Create: `lib/src/features/backup/domain/backup_manifest.dart`
- Create: `lib/src/features/backup/domain/backup_failures.dart`
- Create: `lib/src/features/backup/data/backup_envelope_codec.dart`
- Create: `lib/src/features/backup/data/database_snapshotter.dart`
- Create: `lib/src/features/backup/data/consistent_database_snapshot.dart`
- Create: `lib/src/features/backup/data/file_picker_backup_gateway.dart`
- Create: `lib/src/features/backup/data/mobile_document_export_gateway.dart`
- Create: `lib/src/features/backup/data/mobile_document_import_gateway.dart`
- Create: `android/app/src/main/kotlin/app/biblerecite/BackupDocumentPlugin.kt`
- Create: `ios/Runner/BackupDocumentPlugin.swift`
- Modify: `android/app/src/main/kotlin/app/biblerecite/MainActivity.kt`
- Modify: `ios/Runner/AppDelegate.swift`
- Create: `tool/backup/reference_golden_vector.py`
- Create: `tool/backup/requirements-golden.txt`
- Create: `test/fixtures/backup/golden-v1.brbkp`
- Create: `test/fixtures/backup/golden-v1.json`
- Test: `test/backup/backup_envelope_codec_test.dart`
- Test: `test/backup/backup_file_gateway_test.dart`

**Interfaces:**
- Produces: streaming encrypted export and typed failure categories.
- Consumes: a write-drained, consistent `VACUUM INTO`/SQLite-online-backup snapshot of `user.sqlite` with no WAL sidecars.

- [ ] **Step 1: Write golden-header, round-trip, and tamper tests**

```dart
test('matches the complete independent v1 known-answer vector', () async {
  final vector = await GoldenBackupVector.load('test/fixtures/backup/golden-v1.json');
  final bytes = await File('test/fixtures/backup/golden-v1.brbkp').readAsBytes();
  expect(await sha256Hex(bytes), vector.envelopeSha256);
  expect(parseManifest(bytes), vector.manifest);
  expect(extractHeaderMac(bytes), vector.headerMac);
  expect(extractCiphertext(bytes), vector.ciphertext);
  expect(extractTag(bytes), vector.tag);
  expect(await codec.decryptBytes(bytes, password: vector.password), vector.payloadBytes);
  final generated = await vectorConfiguredCodec.encryptToBytes(
    payload: vector.payloadBytes,
    password: vector.password,
  );
  expect(generated, bytes);
  final tampered = Uint8List.fromList(bytes)..[bytes.length - 20] ^= 1;
  await expectLater(codec.decryptBytes(tampered, password: vector.password), throwsA(isA<BackupAuthenticationFailure>()));
});
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/backup/backup_envelope_codec_test.dart`

Expected: FAIL because codec is missing.

- [ ] **Step 3: Implement the exact v1 envelope**

Add the exact dependencies before implementation:

```powershell
.\.toolchains\flutter\bin\flutter.bat pub add cryptography:2.9.0 archive:4.0.9
```

Create a consistent database input with `VACUUM INTO` (or SQLite's online backup API) after draining application writes; never copy only `user.sqlite` while WAL mode is active. Open the snapshot separately, run integrity/FK checks, and require no `-wal`/`-shm` sidecars before archiving.

Binary layout is exact: 8 ASCII bytes `BRBKP001`; 4-byte unsigned big-endian manifest length (maximum 65536); RFC 8785/JCS canonical UTF-8 JSON manifest; 32-byte HMAC-SHA256 header MAC; exactly `ciphertextLength` XChaCha20 ciphertext bytes; 16-byte Poly1305 tag; then EOF. Reject truncation and trailing bytes. The manifest is:

```json
{
  "format": "bible-recitation-backup",
  "protected": {
    "envelopeVersion": 1,
    "backupSchemaVersion": 1,
    "createdAtUtc": "2026-07-12T12:00:00Z",
    "appVersion": "1.0.0+1",
    "userDatabaseSchemaVersion": 1,
    "requiredScripturePacks": [{"translationId":"fixture-translation","packId":"fixture-pack-v1","versificationId":"fixture-versification-v1","semanticSha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}],
    "payloadFormat": "zip-v1",
    "includesRecordings": false,
    "plaintextLength": 1048576,
    "ciphertextLength": 1048576,
    "passwordEncoding": "utf8-v1",
    "kdf": {"name":"argon2id","version":19,"saltBase64Url":"AAECAwQFBgcICQoLDA0ODw","memoryKiB":19456,"iterations":2,"parallelism":1,"outputLength":64},
    "cipher": {"name":"xchacha20-poly1305","nonceBase64Url":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYX","keyLength":32,"tagLength":16}
  }
}
```

The fixture IDs/hash and example salt/nonce are fixed golden-test values; production writes the installed packs' actual identities, a secure-random 16-byte salt, and a secure-random 24-byte nonce for every export. `BackupEnvelopeCodec` receives injectable random bytes, clock, and app-version providers so the test can reproduce the vector exactly. `reference_golden_vector.py` is an independent implementation pinned by `requirements-golden.txt` to `PyNaCl==1.6.2` and `argon2-cffi==25.1.0`; it creates a deterministic ZIP with fixed file order/timestamps/permissions and emits the complete envelope plus JSON containing the exact manifest, header MAC, ciphertext, tag, payload bytes, and envelope SHA-256. The Dart test never regenerates its expected output.

`utf8-v1` means encode the password's exact Dart Unicode scalar sequence as UTF-8: do not trim, case-fold, or apply NFC/NFKC normalization. Reject any v1 KDF/cipher name, version, parameter, decoded length, or payload length that differs from the allowed schema before allocating. `plaintextLength == ciphertextLength`, both are nonnegative and at most 8 GiB, and the device-specific free-space limit may be lower. Argon2id output is 64 bytes: first 32 bytes are the AEAD key and last 32 bytes are the header-MAC key. Header MAC input and AEAD AAD are both exactly `magic || uint32be(manifestLength) || manifestBytes`; compare the MAC in constant time. A header-MAC or Poly1305 failure returns one generic “密码错误或备份已损坏” authentication failure. Do not add an unauthenticated ciphertext digest; the Poly1305 tag is authoritative.

Store user-kept audio as immutable content-addressed blobs under `recordings/blobs/`, with each filename exactly its 64-character lowercase SHA-256; the database stores hash, byte size, MIME type, and availability, never an arbitrary mutable path. Export's maintenance lease freezes both database writes and recording add/delete operations while it selects blobs. Build the ZIP into a bounded same-volume temporary file first so plaintext/ciphertext length is known, then use `Xchacha20.poly1305Aead().encryptStream`; capture the final tag and assemble the envelope without buffering the payload. Decrypt to an untrusted staging file and do not parse or expose plaintext until the stream finishes and the tag verifies. ZIP permits only `payload-manifest.json`, `user.sqlite`, and optional recording blob entries following that exact prefix/name rule. Reject forward/backward absolute paths, `..`, backslashes, drive letters, UNC prefixes, NUL, Windows device names, symlinks, hard links, device entries, duplicate/case-folding-colliding paths, inconsistent entry hashes, or actual expanded bytes above manifest limits; count bytes written rather than trusting ZIP metadata.

Before export/restore, calculate worst-case simultaneous space for snapshot, ZIP, ciphertext/plaintext staging, candidate, safety copy, and document copy with a 10% margin. Abort before mutation when insufficient. Every failure deletes authenticated/decrypted staging and orphan temp files; startup removes abandoned temp directories only when no valid restore marker references them.

Run Argon2id and archive work off the UI isolate. Desktop file picker returns a path and reads/writes streams. Android/iOS register `BackupDocumentPlugin` from MainActivity/AppDelegate. Export stream-copies the completed temporary envelope to the selected document URI/URL. Import first reads only the fixed 12-byte prefix and at most 65536 manifest bytes through the document handle, validates declared ciphertext/total length and KDF bounds, compares any provider-reported file size, and preflights free space; only then does it bounded-stream exactly the declared total into private staging while counting actual bytes. Never load a 256 MB backup into Dart heap or copy an unbounded hostile URI first.

- [ ] **Step 4: Run crypto, 256 MB stream, and gateway tests**

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/backup/backup_envelope_codec_test.dart test/backup/backup_file_gateway_test.dart
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: PASS; peak Dart heap stays below 96 MB during the 256 MB synthetic export test.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/backup android/app/src/main/kotlin ios/Runner tool/backup test/backup test/fixtures/backup pubspec.yaml pubspec.lock
git commit -m "feat: export encrypted local backups"
```

## Task 9: Restore backups transactionally and recover crashes

**Files:**
- Create: `lib/src/features/backup/data/database_restore_coordinator.dart`
- Create: `lib/src/features/backup/data/atomic_file_swap.dart`
- Create: `lib/src/features/backup/data/restore_transaction_log.dart`
- Create: `lib/src/features/backup/presentation/backup_restore_screen.dart`
- Modify: `lib/l10n/app_zh.arb`
- Modify: `lib/l10n/app_zh_Hant.arb`
- Modify: `lib/l10n/app_en.arb`
- Create: `integration_test/backup_restore_crash_recovery_test.dart`
- Create: `tool/backup/restore_failpoint_parent.dart`
- Create: `tool/backup/restore_failpoint_child.dart`
- Create: `tool/backup/database_lock_holder.dart`
- Create: `android/app/src/androidTest/kotlin/app/biblerecite/RestoreProcessDeathTest.kt`
- Create: `ios/RunnerTests/RestoreProcessDeathTests.swift`
- Test: `test/backup/database_restore_coordinator_test.dart`

**Interfaces:**
- Produces full-replacement restore and startup recovery.
- Consumes verified payload and `ScriptureRepository` for reference checks.

- [ ] **Step 1: Write failpoint tests for every swap phase**

```dart
for (final failpoint in RestoreFailpoint.values) {
  test('restart recovers a complete old or new database after $failpoint', () async {
    final harness = await ProcessDeathRestoreHarness.create();
    final exitCode = await harness.runRestoreChild(failpoint: failpoint);
    expect(exitCode, 137);
    final result = await harness.runFreshRecoveryProcess();
    expect(result.liveDatabaseIsExactlyOldOrNew, isTrue);
    expect(result.foreignKeyViolations, isEmpty);
  });
}
```

- [ ] **Step 2: Run and verify failure**

Run: `.\.toolchains\flutter\bin\flutter.bat test test/backup/database_restore_coordinator_test.dart`

Expected: FAIL for missing restore coordinator.

- [ ] **Step 3: Implement staged validation and logged atomic swap**

Validate magic/limits, header authentication, tag, ZIP paths and entry hashes. Open the untrusted candidate separately and perform this immutable sealing order: migrate it; clear source-device `ReminderRegistrations`; set every recording availability (`notIncluded` when blobs were excluded, otherwise require every `available` row's declared content hash/size/MIME); validate all recording and scripture references; checkpoint with `PRAGMA wal_checkpoint(TRUNCATE)`; run `VACUUM INTO candidate.normalized.sqlite`; close both databases; delete the pre-normalized candidate; and open only `candidate.normalized.sqlite` read-only for `PRAGMA integrity_check`, `foreign_key_check`, logical-content digest, and absence of sidecars. No code may write the normalized candidate after that point, and the marker's new hash refers only to this sealed file. When the exact pack ID, versification ID, and semantic SHA-256 is installed, resolve keys through `ScriptureRepository`; when missing/changed, retain the revision requirement and restore history as “经文包暂不可用” rather than rejecting or silently binding it to same-named different text.

Before publishing `prepared`, install each authenticated recording blob immutably: stream it to a same-directory temporary file; flush and fsync the file contents; verify length and SHA-256; atomically rename it to the lowercase hash filename; then fsync `recordings/blobs/`. If a target already exists, re-verify its bytes; quarantine and replace it if corrupt. A crash may leave an unreferenced valid blob but can never leave a committed database row pointing to a missing or unflushed blob. Garbage-collect unreferenced blobs only after `verified`.

While still owning the process-lifetime lease, enter maintenance mode, drain writes, create the current safety snapshot with `VACUUM INTO`, checkpoint/close live DB, and remove only verified-empty WAL/SHM sidecars. Candidate, live, safety, and marker temp files are siblings in the live database directory, not merely somewhere on the same volume. Flush the sealed normalized candidate and safety file contents, fsync their shared parent directory, and only then publish `prepared`. The marker contains transaction UUID, old/new/safety SHA-256 values, old target-device reminder IDs, recording blob hashes, and one of `prepared`, `installed`, `postCommitPending`, or `verified`. Write each marker as a new temp file, flush it, atomic-rename it, then fsync the parent directory through a native platform adapter.

At `prepared`, live still hashes as old and candidate/safety match the marker. Atomically replace live with candidate: POSIX uses same-directory `rename`; Windows calls `ReplaceFileW(live, candidate, NULL, 0, NULL, NULL)` while retaining the separately verified safety snapshot. Immediately flush the installed file and its parent directory; completion of that flush is the restore commit point. Do not use unsupported `REPLACEFILE_WRITE_THROUGH` and do not add `oldMoved`. Durably write `installed`, open/verify new DB, then `postCommitPending`. Cancel the marker's old target-device reminder IDs, reconcile from restored tasks, and write `verified`. Recovery never trusts phase alone: it hashes live/candidate/safety, applies a documented truth table, restores safety only before the commit point when live is absent/invalid, rejects ambiguous hashes, and completes new-state post-commit work when live has the committed new hash. After commit, the API returns “恢复已提交，正在完成系统更新” if post-commit work is interrupted; it does not report a rollback-style failure.

The backup/restore screen localizes export scope, password guidance, free-space checks, generic authentication failure, future-schema rejection, unavailable scripture revisions, post-commit pending state, and recovery actions in all three ARBs. No diagnostic distinguishes a wrong password from authenticated corruption. Run locale-key parity and `flutter gen-l10n` before the backup widget tests.

- [ ] **Step 4: Run unit and real-filesystem integration tests**

```powershell
.\.toolchains\flutter\bin\flutter.bat test test/backup
.\.toolchains\flutter\bin\dart.bat run tool/backup/restore_failpoint_parent.dart --child tool/backup/restore_failpoint_child.dart
.\.toolchains\flutter\bin\flutter.bat test integration_test/backup_restore_crash_recovery_test.dart -d windows
.\.toolchains\flutter\bin\flutter.bat analyze
```

Expected: all PASS; wrong password/tamper, future schema, disk-full, file-content or directory fsync failure, half-written marker temp, orphan recording blob, pre-existing corrupt recording blob, candidate-created WAL, stale live sidecar, invalid FK, concurrent-write export, and every hard-process-death failpoint yield a readable complete database with the expected logical-content digest. A two-process desktop test starts `database_lock_holder.dart` with an open live connection, then proves a second restore process cannot create staging, markers, blobs, notifications, or any database change before it exits with `InstanceAlreadyRunning`; after the holder exits, restore succeeds. The failpoint parent launches a child, the child calls `exit(137)` at each failpoint without Dart cleanup/finally, and a fresh process performs recovery. Android instrumentation and iOS XCTest terminate/relaunch the app process; macOS and Windows use external process harnesses. All four real filesystems pass in the release matrix.

- [ ] **Step 5: Commit**

```powershell
git add lib/src/features/backup lib/l10n test/backup integration_test/backup_restore_crash_recovery_test.dart tool/backup android/app/src/androidTest ios/RunnerTests windows macos
git commit -m "feat: restore encrypted backups transactionally"
```

## Phase Acceptance

Run code generation, analyze, all tests, database schema verification, plan fixtures, reminder fake reconciliation, 256 MB backup export, encryption tamper cases, and crash-recovery failpoints. The phase is accepted when a completed recitation atomically updates history/mastery/plan/review data; a 30-day plan survives missed days without touching locks; Today and statistics reflect local data; reminders stay under 32; and backup restore always yields a complete old or complete new database, never a merge or partial state.

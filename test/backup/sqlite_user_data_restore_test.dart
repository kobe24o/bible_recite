import 'package:bible_recite/src/features/backup/domain/user_data_backup.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'user_data_backup_test.dart' show backupRecords;

void main() {
  late Database database;
  late SqlitePlanRepository repository;
  setUp(() {
    database = sqlite3.openInMemory();
    repository = SqlitePlanRepository(database);
  });
  tearDown(() => repository.close());

  test(
    'migrates legacy recitation records before exporting a backup',
    () async {
      final legacy = sqlite3.openInMemory();
      legacy.execute('''
      CREATE TABLE recitation_result (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        start_verse INTEGER NOT NULL,
        end_verse INTEGER NOT NULL,
        mode TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        correct_count INTEGER NOT NULL,
        incorrect_count INTEGER NOT NULL,
        omitted_count INTEGER NOT NULL,
        reordered_count INTEGER NOT NULL,
        accuracy REAL NOT NULL,
        completed_at TEXT NOT NULL
      )
    ''');
      final legacyRepository = SqlitePlanRepository(legacy);
      addTearDown(legacyRepository.close);

      final backup = await legacyRepository.exportUserData();

      expect(backup.records['recitation_result'], isEmpty);
    },
  );

  test(
    'exports legacy results after their deleted plan references are cleared',
    () async {
      seedRecords(database);
      database.execute('PRAGMA foreign_keys = OFF');
      database.execute('UPDATE recitation_result SET plan_id = 999');
      database.execute('UPDATE recitation_verse_metric SET plan_id = 999');
      database.execute('UPDATE ebbinghaus_cycle SET source_plan_id = 999');
      database.execute('PRAGMA foreign_keys = ON');

      final backup = await repository.exportUserData();

      expect(backup.records['recitation_result']!.single['plan_ref'], isNull);
      expect(
        backup.records['recitation_verse_metric']!.single['plan_ref'],
        isNull,
      );
      expect(
        backup.records['ebbinghaus_cycle']!.single['source_plan_ref'],
        isNull,
      );
    },
  );

  test(
    'snapshot-detached quiz history round trips without collisions',
    () async {
      final questions = [
        for (final position in [(16, 0), (16, 2), (17, 0)])
          ValidatedQuizQuestion(
            reference: '约翰福音 3:${position.$1}',
            translationId: 'cmn-cu89s',
            bookId: 'JHN',
            chapter: 3,
            verse: position.$1,
            start: position.$2,
            end: position.$2 + 1,
            word: '神',
            partOfSpeech: '名词',
            meaning: '创造主',
            verseText: '神爱世人',
          ),
      ];
      await repository.saveQuizQuestions(questions);
      for (final question in database.select(
        'SELECT id FROM quiz_question ORDER BY id',
      )) {
        await repository.completeQuizQuestion(
          questionId: question['id'] as int,
          correct: true,
          answeredAt: DateTime.utc(2026, 8, 21),
        );
      }
      final attached = await repository.exportUserData();
      await repository.stageQuizBankSnapshot(702, [questions.first]);
      await repository.activateStagedQuizBankSnapshot(702);
      expect(
        database
            .select('SELECT question_id FROM quiz_result')
            .map((r) => r['question_id']),
        [null, null, null],
      );
      final detached = UserDataBackup.decode(
        (await repository.exportUserData()).encode(),
      );
      expect(detached.records['quiz_result']!.map((r) => r['question_ref']), [
        null,
        null,
        null,
      ]);
      expect(
        detached.records['quiz_result']!.map((r) => r['key']),
        attached.records['quiz_result']!.map((r) => r['key']),
      );
      final targetDatabase = sqlite3.openInMemory();
      final target = SqlitePlanRepository(targetDatabase);
      addTearDown(target.close);
      await target.restoreUserData(detached, mode: RestoreMode.replace);
      expect((await target.getQuizSummary()).totalAnswered, 3);
      expect(
        targetDatabase
            .select('SELECT question_id FROM quiz_result')
            .map((r) => r['question_id']),
        [null, null, null],
      );
      expect(
        (await target.exportUserData()).records['quiz_result'],
        detached.records['quiz_result'],
      );
      final report = await target.restoreUserData(
        attached,
        mode: RestoreMode.merge,
      );
      expect(report.categories['quiz_result']!.imported, 0);
      expect(report.categories['quiz_result']!.skipped, 3);
      expect((await target.getQuizSummary()).totalAnswered, 3);
    },
  );

  test(
    'partly completed resumed plan preserves its rebased task dates',
    () async {
      final planId = await repository.createPlan(
        NewMemorizationPlan(
          title: '恢复排期',
          translationId: 'cmn-cu89s',
          bookId: 'GEN',
          startChapter: 1,
          endChapter: 1,
          startDate: DateTime(2020, 1, 1),
          endDate: DateTime(2020, 1, 3),
          tasks: [
            for (var day = 0; day < 3; day++)
              NewPlanTask(
                dayIndex: day,
                startChapter: 1,
                startVerse: day + 1,
                endChapter: 1,
                endVerse: day + 1,
              ),
          ],
        ),
      );
      final first = (await repository.listTasks(planId)).first;
      await repository.setTaskCompleted(first.id, true);
      await repository.pausePlan(planId);
      await repository.resumePlan(planId);
      final tasks = await repository.listTasks(planId);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(tasks.map((task) => task.dueDate), [
        today,
        today,
        today.add(const Duration(days: 1)),
      ]);
      expect(
        (await repository.listPlans()).single.startDate,
        DateTime(2020, 1, 1),
      );
      final backup = UserDataBackup.decode(
        (await repository.exportUserData()).encode(),
      );
      final target = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(target.close);
      await target.restoreUserData(backup, mode: RestoreMode.replace);
      final restoredPlan = (await target.listPlans()).single;
      final restoredTasks = await target.listTasks(restoredPlan.id);
      expect(restoredPlan.startDate, DateTime(2020, 1, 1));
      expect(restoredTasks.map((task) => task.dueDate), [
        today,
        today,
        today.add(const Duration(days: 1)),
      ]);
      expect(restoredTasks.map((task) => task.completed), [true, false, false]);
    },
  );

  test(
    'replacement preserves quiz streak statistics from the backup',
    () async {
      final source = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(source.close);
      await source.setSetting('current_quiz_correct_streak', '7');
      await source.setSetting('max_quiz_correct_streak', '11');
      final backup = await source.exportUserData();
      await repository.setSetting('current_quiz_correct_streak', '2');
      await repository.setSetting('max_quiz_correct_streak', '3');
      await repository.restoreUserData(backup, mode: RestoreMode.replace);
      final summary = await repository.getQuizSummary();
      expect(summary.currentCorrectStreak, 7);
      expect(summary.maxCorrectStreak, 11);
    },
  );

  test(
    'exports and restores a review restarted under its original plan',
    () async {
      seedRecords(database);
      final failedResult = await repository.saveRecitationResult(
        NewRecitationResult(
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          startVerse: 16,
          endVerse: 17,
          mode: 'continuous',
          durationSeconds: 30,
          correctCount: 7,
          incorrectCount: 3,
          omittedCount: 0,
          reorderedCount: 0,
          accuracy: .7,
          completedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      await repository.processEbbinghausResult(
        resultId: failedResult,
        reviewId: 65,
      );
      final backup = await repository.exportUserData();
      expect(backup.records['ebbinghaus_cycle'], hasLength(2));
      final target = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(target.close);
      await target.restoreUserData(backup, mode: RestoreMode.replace);
      expect((await target.exportUserData()).records, backup.records);
    },
  );

  test('replacement can recover a locally inconsistent schedule', () async {
    seedRecords(database);
    database.execute('UPDATE plan_task SET day_index = 999');
    await repository.restoreUserData(
      UserDataBackup.fromRecords({}),
      mode: RestoreMode.replace,
    );
    expect(await repository.listPlans(), isEmpty);
  });

  test(
    'exports all user tables and restores their foreign keys with new row IDs',
    () async {
      final sourceDatabase = sqlite3.openInMemory();
      final source = SqlitePlanRepository(sourceDatabase);
      addTearDown(source.close);
      seedRecords(sourceDatabase);
      final backup = UserDataBackup.decode(
        (await source.exportUserData()).encode(),
      );
      await repository.createPlan(localPlan);
      final report = await repository.restoreUserData(
        backup,
        mode: RestoreMode.merge,
      );
      expect((await repository.listPlans()).length, 2);
      final imported = database
          .select("SELECT id FROM memorization_plan WHERE title = '恩典之路'")
          .single['id'];
      expect(imported, isNot(12));
      expect(
        database
            .select('SELECT plan_id FROM recitation_result')
            .single['plan_id'],
        imported,
      );
      expect(database.select('PRAGMA foreign_key_check'), isEmpty);
      final exported = await repository.exportUserData();
      expect(
        exported.records['recitation_result'],
        backup.records['recitation_result'],
      );
      expect(exported.records['quiz_result'], backup.records['quiz_result']);
      expect(
        exported.records['ebbinghaus_review'],
        backup.records['ebbinghaus_review'],
      );
      expect(report.categories['recitation_result']!.imported, 1);
      expect(report.categories['memorization_plan']!.retained, 1);
      expect((await repository.listPlans()).first.days, 400);
      expect(
        (await repository.listTasks(imported as int)).single.completed,
        isTrue,
      );
    },
  );

  test(
    'merging the same backup twice skips duplicates across all categories',
    () async {
      final backup = UserDataBackup.fromRecords(backupRecords());
      await repository.restoreUserData(backup, mode: RestoreMode.merge);
      final report = await repository.restoreUserData(
        backup,
        mode: RestoreMode.merge,
      );
      expect(report.imported, 0);
      for (final name in backup.records.keys) {
        expect(
          report.categories[name]!.skipped,
          backup.records[name]!.length,
          reason: name,
        );
      }
      expect(database.select('SELECT * FROM quiz_result').length, 1);
      expect(
        database.select('SELECT * FROM recitation_verse_metric').length,
        1,
      );
    },
  );

  test(
    'merge uses newer note and preserves local notes on timestamp ties',
    () async {
      final day = DateTime(2026, 1, 1);
      final backup = UserDataBackup.fromRecords(backupRecords());
      await repository.saveDevotionNote(
        day,
        '旧笔记',
        updatedAt: DateTime.utc(2026),
      );
      var report = await repository.restoreUserData(
        backup,
        mode: RestoreMode.merge,
      );
      expect((await repository.devotionNoteFor(day))!.content, '今天的领受');
      expect(report.categories['devotion_note']!.imported, 1);
      await repository.saveDevotionNote(
        day,
        '同时间保留',
        updatedAt: DateTime.utc(2026, 1, 1, 1),
      );
      report = await repository.restoreUserData(
        backup,
        mode: RestoreMode.merge,
      );
      expect((await repository.devotionNoteFor(day))!.content, '同时间保留');
      expect(report.categories['devotion_note']!.retained, 1);
      await repository.saveDevotionNote(
        day,
        '',
        updatedAt: DateTime.utc(2026, 1, 2),
      );
      await repository.restoreUserData(backup, mode: RestoreMode.merge);
      expect((await repository.devotionNoteFor(day))!.content, '');
    },
  );

  test(
    'merge preserves local settings, task progress and achievements',
    () async {
      seedRecords(database);
      database.execute('UPDATE plan_task SET completed = 0');
      database.execute('UPDATE achievement_unlock SET award_count = 3');
      await repository.setSetting('profile_name', '本机名字');
      final backup = UserDataBackup.fromRecords(backupRecords());
      await repository.restoreUserData(backup, mode: RestoreMode.merge);
      expect(
        database.select('SELECT completed FROM plan_task').single['completed'],
        1,
      );
      expect(
        database
            .select('SELECT award_count FROM achievement_unlock')
            .single['award_count'],
        3,
      );
      expect(await repository.getSetting('profile_name', ''), '本机名字');
    },
  );

  for (final mode in RestoreMode.values) {
    test(
      '${mode.name} keeps secrets, caches, staging and unrelated scripture tables',
      () async {
        await repository.setSetting('quiz_model_api_key', 'local-secret');
        await repository.setSetting('devotion_cached_manifest', 'local-cache');
        await repository.setSetting('quiz_bank_revision', '42');
        database.execute('CREATE TABLE scripture_pack_fixture (content TEXT)');
        database.execute(
          "INSERT INTO scripture_pack_fixture VALUES ('scripture')",
        );
        database.execute(
          '''INSERT INTO quiz_bank_snapshot_staging
        (revision, translation_id, book_id, chapter, verse, start_offset, end_offset,
         word, part_of_speech, meaning, reference, staged_at)
        VALUES (1, 'cmn-cu89s', 'JHN', 3, 16, 2, 4, '世人', '名词', '人类', 'JHN3:16', '2026-01-01T00:00:00Z')''',
        );
        await repository.restoreUserData(
          UserDataBackup.fromRecords(backupRecords()),
          mode: mode,
        );
        expect(
          await repository.getSetting('quiz_model_api_key', ''),
          'local-secret',
        );
        expect(
          await repository.getSetting('devotion_cached_manifest', ''),
          'local-cache',
        );
        expect(await repository.getSetting('quiz_bank_revision', ''), '42');
        expect(
          database
              .select('SELECT * FROM scripture_pack_fixture')
              .single['content'],
          'scripture',
        );
        expect(
          database.select('SELECT * FROM quiz_bank_snapshot_staging').length,
          1,
        );
        expect(
          (await repository.exportUserData()).encode(),
          isNot(contains('local-secret')),
        );
      },
    );

    test(
      '${mode.name} rolls every table back when a late insert fails',
      () async {
        await repository.createPlan(localPlan);
        await repository.saveDevotionNote(DateTime(2025, 12, 31), '保留');
        await repository.setSetting('profile_name', '本机');
        final before = (await repository.exportUserData()).records;
        database.execute(
          """CREATE TRIGGER fail_restore BEFORE INSERT ON devotion_note
        BEGIN SELECT RAISE(ABORT, 'injected write failure'); END""",
        );
        await expectLater(
          repository.restoreUserData(
            UserDataBackup.fromRecords(backupRecords()),
            mode: mode,
          ),
          throwsA(isA<SqliteException>()),
        );
        expect((await repository.exportUserData()).records, before);
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
        database.execute('DROP TRIGGER fail_restore');
        await repository.setSetting('profile_name', '事务已关闭');
        expect(await repository.getSetting('profile_name', ''), '事务已关闭');
      },
    );
  }

  test(
    'replacement removes absent records and restores singleton defaults',
    () async {
      seedRecords(database);
      await repository.restoreUserData(
        UserDataBackup.fromRecords({}),
        mode: RestoreMode.replace,
      );
      expect(await repository.listPlans(), isEmpty);
      expect(await repository.devotionNoteFor(DateTime(2026)), isNull);
      expect(database.select('SELECT * FROM quiz_question'), isEmpty);
      expect(database.select('SELECT * FROM recitation_result'), isEmpty);
      expect(database.select('SELECT * FROM achievement_unlock'), isEmpty);
      expect(database.select('SELECT * FROM ebbinghaus_cycle'), isEmpty);
      expect((await repository.getEbbinghausSettings()).passThreshold, 0.8);
      expect(await repository.getSetting('profile_name', 'default'), 'default');
    },
  );

  test('replacement reproduces all portable rows', () async {
    final backup = UserDataBackup.fromRecords(backupRecords());
    await repository.createPlan(localPlan);
    await repository.restoreUserData(backup, mode: RestoreMode.replace);
    expect((await repository.exportUserData()).records, backup.records);
  });

  test(
    'merge rolls back incompatible parent schedules rather than leaving an invalid graph',
    () async {
      final rows = backupRecords();
      await repository.restoreUserData(
        UserDataBackup.fromRecords(rows),
        mode: RestoreMode.replace,
      );
      database.execute('DELETE FROM plan_schedule_span');
      database.execute(
        "UPDATE memorization_plan SET days = 1, end_date = '2026-01-01'",
      );
      final before = (await repository.exportUserData()).records;
      rows['plan_schedule_span'] = [];
      rows['plan_task']!.single['day_index'] = 2;
      rows['plan_task']!.single['due_date'] = '2026-01-03';
      await expectLater(
        repository.restoreUserData(
          UserDataBackup.fromRecords(rows),
          mode: RestoreMode.merge,
        ),
        throwsFormatException,
      );
      expect((await repository.exportUserData()).records, before);
    },
  );
}

void seedRecords(Database database) {
  for (final entry in backupRecords().entries) {
    for (final row in entry.value) {
      database.execute(
        'INSERT OR REPLACE INTO ${entry.key} (${row.keys.join(', ')}) VALUES (${List.filled(row.length, '?').join(', ')})',
        row.values.toList(),
      );
    }
  }
}

final localPlan = NewMemorizationPlan(
  title: '本机计划',
  translationId: 'cmn-cu89s',
  bookId: 'GEN',
  startChapter: 1,
  endChapter: 1,
  startDate: DateTime(2026, 9, 17),
  endDate: DateTime(2026, 9, 17),
  tasks: const [
    NewPlanTask(
      dayIndex: 0,
      startChapter: 1,
      startVerse: 1,
      endChapter: 1,
      endVerse: 2,
    ),
  ],
);

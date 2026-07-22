import 'package:sqlite3/sqlite3.dart';

import '../../review/domain/ebbinghaus_models.dart';
import '../../review/domain/ebbinghaus_scheduler.dart';
import '../../statistics/domain/achievement.dart';
import '../../statistics/domain/achievement_engine.dart';
import '../../statistics/domain/recitation_result.dart';
import '../domain/plan_models.dart';

final class SqlitePlanRepository {
  SqlitePlanRepository(this._database) {
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS memorization_plan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        start_chapter INTEGER NOT NULL CHECK(start_chapter > 0),
        end_chapter INTEGER NOT NULL CHECK(end_chapter >= start_chapter),
        days INTEGER NOT NULL CHECK(days BETWEEN 1 AND 365),
        start_date TEXT NOT NULL,
        end_date TEXT,
        source_kind TEXT NOT NULL DEFAULT 'local',
        source_url TEXT,
        external_id TEXT,
        revision INTEGER NOT NULL DEFAULT 0,
        content_locked INTEGER NOT NULL DEFAULT 0 CHECK(content_locked IN (0, 1)),
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS plan_task (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL REFERENCES memorization_plan(id) ON DELETE CASCADE,
        day_index INTEGER NOT NULL CHECK(day_index >= 0),
        due_date TEXT NOT NULL,
        book_id TEXT,
        start_chapter INTEGER NOT NULL CHECK(start_chapter > 0),
        start_verse INTEGER NOT NULL CHECK(start_verse > 0),
        end_chapter INTEGER NOT NULL CHECK(end_chapter >= start_chapter),
        end_verse INTEGER NOT NULL CHECK(end_verse > 0),
        completed INTEGER NOT NULL DEFAULT 0 CHECK(completed IN (0, 1)),
        UNIQUE(plan_id, day_index)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS recitation_result (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        start_verse INTEGER NOT NULL,
        end_verse INTEGER NOT NULL,
        chapter_verse_count INTEGER NOT NULL DEFAULT 0,
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
    _database.execute('''
      CREATE TABLE IF NOT EXISTS achievement_unlock (
        achievement_id TEXT PRIMARY KEY,
        unlocked_at TEXT NOT NULL,
        source TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS app_setting (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS ebbinghaus_settings (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0, 1)),
        pass_threshold REAL NOT NULL DEFAULT 0.8
          CHECK(pass_threshold BETWEEN 0.5 AND 1.0),
        enabled_at TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    _database.execute(
      '''
      INSERT OR IGNORE INTO ebbinghaus_settings
      (id, enabled, pass_threshold, enabled_at, updated_at)
      VALUES (1, 0, 0.8, NULL, ?)
    ''',
      [DateTime.now().toUtc().toIso8601String()],
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS ebbinghaus_cycle (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_result_id INTEGER NOT NULL UNIQUE
          REFERENCES recitation_result(id) ON DELETE CASCADE,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        base_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK(status IN ('active', 'completed', 'restarted', 'paused')),
        created_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS ebbinghaus_review (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_id INTEGER NOT NULL
          REFERENCES ebbinghaus_cycle(id) ON DELETE CASCADE,
        interval_days INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
          CHECK(status IN ('pending', 'completed', 'failed', 'cancelled')),
        result_id INTEGER REFERENCES recitation_result(id) ON DELETE SET NULL,
        created_at TEXT NOT NULL,
        UNIQUE(cycle_id, interval_days)
      )
    ''');
    final columns = _database
        .select('PRAGMA table_info(memorization_plan)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!columns.contains('end_date')) {
      _database.execute(
        'ALTER TABLE memorization_plan ADD COLUMN end_date TEXT',
      );
    }
    if (!columns.contains('source_kind')) {
      _database.execute(
        "ALTER TABLE memorization_plan ADD COLUMN source_kind TEXT NOT NULL DEFAULT 'local'",
      );
    }
    if (!columns.contains('source_url')) {
      _database.execute(
        'ALTER TABLE memorization_plan ADD COLUMN source_url TEXT',
      );
    }
    if (!columns.contains('external_id')) {
      _database.execute(
        'ALTER TABLE memorization_plan ADD COLUMN external_id TEXT',
      );
    }
    if (!columns.contains('revision')) {
      _database.execute(
        'ALTER TABLE memorization_plan ADD COLUMN revision INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!columns.contains('content_locked')) {
      _database.execute(
        'ALTER TABLE memorization_plan ADD COLUMN content_locked INTEGER NOT NULL DEFAULT 0',
      );
    }
    final taskColumns = _database
        .select('PRAGMA table_info(plan_task)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!taskColumns.contains('book_id')) {
      _database.execute('ALTER TABLE plan_task ADD COLUMN book_id TEXT');
    }
    _database.execute('''UPDATE plan_task
      SET book_id = (SELECT book_id FROM memorization_plan
        WHERE memorization_plan.id = plan_task.plan_id)
      WHERE book_id IS NULL''');
    _database.execute('''CREATE UNIQUE INDEX IF NOT EXISTS
      idx_plan_cloud_identity ON memorization_plan(source_url, external_id)
      WHERE source_url IS NOT NULL AND external_id IS NOT NULL''');
    _database.execute('''UPDATE memorization_plan
      SET end_date = date(start_date, '+' || (days - 1) || ' days')
      WHERE end_date IS NULL''');
    final resultColumns = _database
        .select('PRAGMA table_info(recitation_result)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!resultColumns.contains('chapter_verse_count')) {
      _database.execute(
        'ALTER TABLE recitation_result ADD COLUMN chapter_verse_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    _database.execute('PRAGMA user_version = 5');
  }

  final Database _database;

  Future<int> createPlan(NewMemorizationPlan plan) async {
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        '''INSERT INTO memorization_plan
        (title, translation_id, book_id, start_chapter, end_chapter, days,
         start_date, end_date, source_kind, source_url, external_id, revision,
         content_locked, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          plan.title,
          plan.translationId,
          plan.bookId,
          plan.startChapter,
          plan.endChapter,
          plan.days,
          _date(plan.startDate),
          _date(plan.endDate),
          plan.sourceKind.name,
          plan.sourceUrl,
          plan.externalId,
          plan.revision,
          plan.contentLocked ? 1 : 0,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      final id = _database.lastInsertRowId;
      for (final task in plan.tasks) {
        final dueDate = plan.startDate.add(Duration(days: task.dayIndex));
        _database.execute(
          '''INSERT INTO plan_task
          (plan_id, day_index, due_date, book_id, start_chapter, start_verse,
           end_chapter, end_verse) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            id,
            task.dayIndex,
            _date(dueDate),
            task.bookId ?? plan.bookId,
            task.startChapter,
            task.startVerse,
            task.endChapter,
            task.endVerse,
          ],
        );
      }
      _database.execute('COMMIT');
      await evaluateAndUnlockAchievements(source: 'plan');
      return id;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<MemorizationPlan>> listPlans() async {
    return _database
        .select('''
      SELECT p.*,
        COUNT(t.id) AS total_tasks,
        COALESCE(SUM(t.completed), 0) AS completed_tasks
      FROM memorization_plan p
      LEFT JOIN plan_task t ON t.plan_id = p.id
      GROUP BY p.id
      ORDER BY p.id DESC
    ''')
        .map(_planFromRow)
        .toList(growable: false);
  }

  Future<String> getSetting(String key, String fallback) async {
    final rows = _database.select(
      'SELECT setting_value FROM app_setting WHERE setting_key = ?',
      [key],
    );
    return rows.isEmpty ? fallback : rows.single['setting_value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    _database.execute(
      '''
      INSERT INTO app_setting(setting_key, setting_value) VALUES (?, ?)
      ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value
    ''',
      [key, value],
    );
  }

  Future<MemorizationPlan?> findPlanBySource(
    String sourceUrl,
    String externalId,
  ) async {
    final rows = _database.select(
      '''
      SELECT p.*,
        COUNT(t.id) AS total_tasks,
        COALESCE(SUM(t.completed), 0) AS completed_tasks
      FROM memorization_plan p
      LEFT JOIN plan_task t ON t.plan_id = p.id
      WHERE p.source_url = ? AND p.external_id = ?
      GROUP BY p.id
      LIMIT 1
    ''',
      [sourceUrl, externalId],
    );
    return rows.isEmpty ? null : _planFromRow(rows.single);
  }

  Future<List<PlanTask>> listTasks(int planId) async {
    return _database
        .select(
          'SELECT * FROM plan_task WHERE plan_id = ? ORDER BY day_index',
          [planId],
        )
        .map(_taskFromRow)
        .toList(growable: false);
  }

  /// Appends passages as new daily tasks.  Keeping their original book on each
  /// task (rather than on the plan header) is what permits one plan to span
  /// chapters and books.
  Future<void> appendDailyTasks(
    MemorizationPlan plan,
    List<NewPlanTask> passages,
  ) async {
    if (plan.contentLocked) {
      throw StateError('云端计划的经文内容不能修改');
    }
    if (passages.isEmpty) return;
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (var index = 0; index < passages.length; index++) {
        final task = passages[index];
        final dayIndex = plan.days + index;
        final dueDate = plan.startDate.add(Duration(days: dayIndex));
        _database.execute(
          '''INSERT INTO plan_task
          (plan_id, day_index, due_date, book_id, start_chapter, start_verse,
           end_chapter, end_verse) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            plan.id,
            dayIndex,
            _date(dueDate),
            task.bookId ?? plan.bookId,
            task.startChapter,
            task.startVerse,
            task.endChapter,
            task.endVerse,
          ],
        );
      }
      final days = plan.days + passages.length;
      final endDate = plan.startDate.add(Duration(days: days - 1));
      _database.execute(
        'UPDATE memorization_plan SET days = ?, end_date = ? WHERE id = ?',
        [days, _date(endDate), plan.id],
      );
      _database.execute('COMMIT');
      await evaluateAndUnlockAchievements(source: 'plan');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<PlanTask>> dueTasks(
    DateTime date, {
    bool includeCompleted = false,
  }) async {
    final value = _date(date);
    return _database
        .select(
          includeCompleted
              ? '''SELECT * FROM plan_task
                WHERE (completed = 0 AND due_date <= ?)
                   OR (completed = 1 AND due_date = ?)
                ORDER BY completed, due_date, id'''
              : '''SELECT * FROM plan_task
                WHERE completed = 0 AND due_date <= ?
                ORDER BY due_date, id''',
          includeCompleted ? [value, value] : [value],
        )
        .map(_taskFromRow)
        .toList(growable: false);
  }

  Future<void> updatePlan(int planId, NewMemorizationPlan plan) async {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final completedDays = _database
          .select(
            'SELECT day_index FROM plan_task WHERE plan_id = ? AND completed = 1',
            [planId],
          )
          .map((row) => row['day_index'] as int)
          .toSet();
      _database.execute(
        '''UPDATE memorization_plan SET title = ?, translation_id = ?,
        book_id = ?, start_chapter = ?, end_chapter = ?, days = ?,
        start_date = ?, end_date = ?, source_kind = ?, source_url = ?,
        external_id = ?, revision = ?, content_locked = ? WHERE id = ?''',
        [
          plan.title,
          plan.translationId,
          plan.bookId,
          plan.startChapter,
          plan.endChapter,
          plan.days,
          _date(plan.startDate),
          _date(plan.endDate),
          plan.sourceKind.name,
          plan.sourceUrl,
          plan.externalId,
          plan.revision,
          plan.contentLocked ? 1 : 0,
          planId,
        ],
      );
      _database.execute('DELETE FROM plan_task WHERE plan_id = ?', [planId]);
      for (final task in plan.tasks) {
        final dueDate = plan.startDate.add(Duration(days: task.dayIndex));
        _database.execute(
          '''INSERT INTO plan_task
          (plan_id, day_index, due_date, book_id, start_chapter, start_verse,
           end_chapter, end_verse, completed)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
          [
            planId,
            task.dayIndex,
            _date(dueDate),
            task.bookId ?? plan.bookId,
            task.startChapter,
            task.startVerse,
            task.endChapter,
            task.endVerse,
            completedDays.contains(task.dayIndex) ? 1 : 0,
          ],
        );
      }
      _database.execute('COMMIT');
      await evaluateAndUnlockAchievements(source: 'plan');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> deletePlan(int planId) async {
    _database.execute('DELETE FROM memorization_plan WHERE id = ?', [planId]);
  }

  Future<void> setTaskCompleted(int taskId, bool completed) async {
    _database.execute('UPDATE plan_task SET completed = ? WHERE id = ?', [
      completed ? 1 : 0,
      taskId,
    ]);
    await evaluateAndUnlockAchievements(source: 'plan');
  }

  Future<int> saveRecitationResult(NewRecitationResult result) async {
    _database.execute(
      '''INSERT INTO recitation_result
      (translation_id, book_id, chapter, start_verse, end_verse,
       chapter_verse_count, mode,
       duration_seconds, correct_count, incorrect_count, omitted_count,
       reordered_count, accuracy, completed_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        result.translationId,
        result.bookId,
        result.chapter,
        result.startVerse,
        result.endVerse,
        result.chapterVerseCount,
        result.mode,
        result.durationSeconds,
        result.correctCount,
        result.incorrectCount,
        result.omittedCount,
        result.reorderedCount,
        result.accuracy,
        result.completedAt.toUtc().toIso8601String(),
      ],
    );
    return _database.lastInsertRowId;
  }

  Future<EbbinghausSettings> getEbbinghausSettings() async {
    final row = _database
        .select(
          'SELECT enabled, pass_threshold, enabled_at FROM ebbinghaus_settings '
          'WHERE id = 1',
        )
        .single;
    return EbbinghausSettings(
      enabled: (row['enabled'] as int) == 1,
      passThreshold: (row['pass_threshold'] as num).toDouble(),
      enabledAt: row['enabled_at'] == null
          ? null
          : DateTime.parse(row['enabled_at'] as String).toLocal(),
    );
  }

  Future<void> updateEbbinghausSettings({
    required bool enabled,
    required double passThreshold,
    DateTime? now,
  }) async {
    final current = await getEbbinghausSettings();
    final changedAt = (now ?? DateTime.now()).toUtc();
    final threshold = passThreshold.clamp(0.5, 1.0).toDouble();
    final enabling = enabled && !current.enabled;
    _database.execute(
      '''UPDATE ebbinghaus_settings SET enabled = ?, pass_threshold = ?,
      enabled_at = ?, updated_at = ? WHERE id = 1''',
      [
        enabled ? 1 : 0,
        threshold,
        enabling
            ? changedAt.toIso8601String()
            : current.enabledAt?.toUtc().toIso8601String(),
        changedAt.toIso8601String(),
      ],
    );
    if (!enabled && current.enabled) {
      _database.execute(
        "UPDATE ebbinghaus_cycle SET status = 'paused' WHERE status = 'active'",
      );
    }
  }

  Future<void> processEbbinghausResult({
    required int resultId,
    int? reviewId,
  }) async {
    final settings = await getEbbinghausSettings();
    if (!settings.enabled || settings.enabledAt == null) return;
    final resultRows = _database.select(
      'SELECT * FROM recitation_result WHERE id = ?',
      [resultId],
    );
    if (resultRows.isEmpty) return;
    final result = resultRows.single;
    final completedAt = DateTime.parse(result['completed_at'] as String);
    if (completedAt.isBefore(settings.enabledAt!.toUtc())) return;
    final passed = const EbbinghausScheduler().passes(
      accuracy: (result['accuracy'] as num).toDouble(),
      threshold: settings.passThreshold,
    );

    _database.execute('BEGIN IMMEDIATE');
    try {
      if (reviewId != null) {
        final rows = _database.select(
          '''
          SELECT r.id, r.cycle_id FROM ebbinghaus_review r
          JOIN ebbinghaus_cycle c ON c.id = r.cycle_id
          WHERE r.id = ? AND r.status = 'pending' AND c.status = 'active'
        ''',
          [reviewId],
        );
        if (rows.isNotEmpty) {
          final cycleId = rows.single['cycle_id'] as int;
          if (passed) {
            _database.execute(
              "UPDATE ebbinghaus_review SET status = 'completed', result_id = ? "
              'WHERE id = ?',
              [resultId, reviewId],
            );
            final remaining =
                _database.select(
                      "SELECT COUNT(*) AS count FROM ebbinghaus_review "
                      "WHERE cycle_id = ? AND status = 'pending'",
                      [cycleId],
                    ).single['count']
                    as int;
            if (remaining == 0) {
              _database.execute(
                "UPDATE ebbinghaus_cycle SET status = 'completed' WHERE id = ?",
                [cycleId],
              );
            }
          } else {
            _database.execute(
              "UPDATE ebbinghaus_review SET status = 'failed', result_id = ? "
              'WHERE id = ?',
              [resultId, reviewId],
            );
            _database.execute(
              "UPDATE ebbinghaus_review SET status = 'cancelled' "
              "WHERE cycle_id = ? AND status = 'pending'",
              [cycleId],
            );
            _database.execute(
              "UPDATE ebbinghaus_cycle SET status = 'restarted' WHERE id = ?",
              [cycleId],
            );
            _insertEbbinghausCycle(result, resultId, completedAt);
          }
        }
      } else if (passed) {
        final duplicate = _database.select(
          'SELECT id FROM ebbinghaus_cycle WHERE source_result_id = ?',
          [resultId],
        );
        final active = _database.select(
          '''
          SELECT id FROM ebbinghaus_cycle
          WHERE translation_id = ? AND book_id = ? AND chapter = ?
            AND status = 'active'
        ''',
          [result['translation_id'], result['book_id'], result['chapter']],
        );
        if (duplicate.isEmpty && active.isEmpty) {
          _insertEbbinghausCycle(result, resultId, completedAt);
        }
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void _insertEbbinghausCycle(Row result, int resultId, DateTime baseDate) {
    final createdAt = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      '''
      INSERT INTO ebbinghaus_cycle
      (source_result_id, translation_id, book_id, chapter, base_date,
       status, created_at) VALUES (?, ?, ?, ?, ?, 'active', ?)
    ''',
      [
        resultId,
        result['translation_id'],
        result['book_id'],
        result['chapter'],
        _date(baseDate.toLocal()),
        createdAt,
      ],
    );
    final cycleId = _database.lastInsertRowId;
    for (final interval in EbbinghausScheduler.intervals) {
      final dueDate = baseDate.toLocal().add(Duration(days: interval));
      _database.execute(
        '''
        INSERT INTO ebbinghaus_review
        (cycle_id, interval_days, due_date, status, created_at)
        VALUES (?, ?, ?, 'pending', ?)
      ''',
        [cycleId, interval, _date(dueDate), createdAt],
      );
    }
  }

  Future<List<EbbinghausReview>> dueEbbinghausReviews(DateTime date) async {
    final settings = await getEbbinghausSettings();
    if (!settings.enabled) return const [];
    return _database
        .select(
          '''
          SELECT r.id, r.cycle_id, r.interval_days, r.due_date,
            c.translation_id, c.book_id, c.chapter
          FROM ebbinghaus_review r
          JOIN ebbinghaus_cycle c ON c.id = r.cycle_id
          WHERE r.status = 'pending' AND c.status = 'active'
            AND r.due_date <= ?
          ORDER BY r.due_date, r.id
        ''',
          [_date(date)],
        )
        .map(
          (row) => EbbinghausReview(
            id: row['id'] as int,
            cycleId: row['cycle_id'] as int,
            translationId: row['translation_id'] as String,
            bookId: row['book_id'] as String,
            chapter: row['chapter'] as int,
            intervalDays: row['interval_days'] as int,
            dueDate: DateTime.parse(row['due_date'] as String),
            completed: false,
          ),
        )
        .toList(growable: false);
  }

  Future<List<AchievementUnlock>> evaluateAndUnlockAchievements({
    String source = 'backfill',
  }) async {
    final progress = const AchievementEngine().evaluate(_achievementSnapshot());
    final existing = _database
        .select('SELECT achievement_id FROM achievement_unlock')
        .map((row) => row['achievement_id'] as String)
        .toSet();
    final now = DateTime.now();
    final unlocked = <AchievementUnlock>[];
    for (final item in progress) {
      if (!item.satisfied || existing.contains(item.definition.id)) continue;
      _database.execute(
        '''INSERT OR IGNORE INTO achievement_unlock
        (achievement_id, unlocked_at, source) VALUES (?, ?, ?)''',
        [item.definition.id, now.toUtc().toIso8601String(), source],
      );
      unlocked.add(
        AchievementUnlock(
          definition: item.definition,
          unlockedAt: now,
          source: source,
        ),
      );
    }
    return unlocked;
  }

  Future<List<AchievementProgress>> listAchievementProgress() async {
    final evaluated = const AchievementEngine().evaluate(
      _achievementSnapshot(),
    );
    final unlockRows = _database.select('SELECT * FROM achievement_unlock');
    final unlocks = <String, DateTime>{
      for (final row in unlockRows)
        row['achievement_id'] as String: DateTime.parse(
          row['unlocked_at'] as String,
        ).toLocal(),
    };
    return [
      for (final item in evaluated)
        AchievementProgress(
          definition: item.definition,
          current: item.current,
          satisfied: item.satisfied,
          unlockedAt: unlocks[item.definition.id],
        ),
    ];
  }

  AchievementSnapshot _achievementSnapshot() {
    final resultRows = _database.select('SELECT * FROM recitation_result');
    final sessionCount = resultRows.length;
    var completedVerses = 0;
    var maxAccuracy = 0.0;
    var hasPerfectLongResult = false;
    final activeDates = <DateTime>{};
    final chapterCoverage = <String, Set<int>>{};
    final chapterSizes = <String, int>{};
    for (final row in resultRows) {
      final startVerse = row['start_verse'] as int;
      final endVerse = row['end_verse'] as int;
      completedVerses += endVerse - startVerse + 1;
      final accuracy = (row['accuracy'] as num).toDouble();
      if (accuracy > maxAccuracy) maxAccuracy = accuracy;
      if (accuracy >= 1 && (row['correct_count'] as int) >= 20) {
        hasPerfectLongResult = true;
      }
      final completedAt = DateTime.parse(
        row['completed_at'] as String,
      ).toLocal();
      activeDates.add(
        DateTime(completedAt.year, completedAt.month, completedAt.day),
      );
      final key = '${row['book_id']}:${row['chapter']}';
      chapterCoverage.putIfAbsent(key, () => <int>{}).addAll([
        for (var verse = startVerse; verse <= endVerse; verse++) verse,
      ]);
      final size = row['chapter_verse_count'] as int;
      if (size > (chapterSizes[key] ?? 0)) chapterSizes[key] = size;
    }
    var maxStreak = 0;
    var streak = 0;
    DateTime? previous;
    final sortedDates = activeDates.toList()..sort();
    for (final date in sortedDates) {
      if (previous != null && date.difference(previous).inDays == 1) {
        streak++;
      } else {
        streak = 1;
      }
      if (streak > maxStreak) maxStreak = streak;
      previous = date;
    }
    final completedChapters = chapterCoverage.entries.where((entry) {
      final required = chapterSizes[entry.key] ?? 0;
      return required > 0 && entry.value.length >= required;
    }).length;
    final planCount =
        _database
                .select('SELECT COUNT(*) AS count FROM memorization_plan')
                .single['count']
            as int;
    final completedPlanCount =
        _database.select('''
      SELECT COUNT(*) AS count FROM (
        SELECT p.id FROM memorization_plan p
        JOIN plan_task t ON t.plan_id = p.id
        GROUP BY p.id
        HAVING COUNT(t.id) > 0 AND SUM(t.completed) = COUNT(t.id)
      )
    ''').single['count']
            as int;
    return AchievementSnapshot(
      sessionCount: sessionCount,
      activeDayStreak: maxStreak,
      completedVerses: completedVerses,
      maxAccuracy: maxAccuracy,
      hasPerfectLongResult: hasPerfectLongResult,
      completedChapters: completedChapters,
      planCount: planCount,
      completedPlanCount: completedPlanCount,
    );
  }

  Future<List<RecitationResult>> listRecitationResults({int limit = 50}) async {
    return _database
        .select(
          'SELECT * FROM recitation_result ORDER BY completed_at DESC, id DESC LIMIT ?',
          [limit],
        )
        .map(_resultFromRow)
        .toList(growable: false);
  }

  Future<RecitationSummary> getRecitationSummary() async {
    final row = _database.select('''
      SELECT COUNT(*) AS total_sessions,
        COALESCE(SUM(end_verse - start_verse + 1), 0) AS total_verses,
        COALESCE(SUM(duration_seconds), 0) AS total_seconds,
        COALESCE(AVG(accuracy), 0) AS average_accuracy
      FROM recitation_result
    ''').single;
    return RecitationSummary(
      totalSessions: row['total_sessions'] as int,
      totalVerses: row['total_verses'] as int,
      totalSeconds: row['total_seconds'] as int,
      averageAccuracy: (row['average_accuracy'] as num).toDouble(),
    );
  }

  Future<void> markCompleted(int taskId) async {
    await setTaskCompleted(taskId, true);
  }

  MemorizationPlan _planFromRow(Row row) => MemorizationPlan(
    id: row['id'] as int,
    title: row['title'] as String,
    translationId: row['translation_id'] as String,
    bookId: row['book_id'] as String,
    startChapter: row['start_chapter'] as int,
    endChapter: row['end_chapter'] as int,
    days: row['days'] as int,
    startDate: DateTime.parse(row['start_date'] as String),
    endDate: DateTime.parse(row['end_date'] as String),
    completedTasks: row['completed_tasks'] as int,
    totalTasks: row['total_tasks'] as int,
    sourceKind: PlanSourceKind.values.firstWhere(
      (value) => value.name == row['source_kind'],
      orElse: () => PlanSourceKind.local,
    ),
    sourceUrl: row['source_url'] as String?,
    externalId: row['external_id'] as String?,
    revision: row['revision'] as int,
    contentLocked: (row['content_locked'] as int) == 1,
  );

  PlanTask _taskFromRow(Row row) => PlanTask(
    id: row['id'] as int,
    planId: row['plan_id'] as int,
    dayIndex: row['day_index'] as int,
    dueDate: DateTime.parse(row['due_date'] as String),
    bookId: row['book_id'] as String,
    startChapter: row['start_chapter'] as int,
    startVerse: row['start_verse'] as int,
    endChapter: row['end_chapter'] as int,
    endVerse: row['end_verse'] as int,
    completed: (row['completed'] as int) == 1,
  );

  RecitationResult _resultFromRow(Row row) => RecitationResult(
    id: row['id'] as int,
    translationId: row['translation_id'] as String,
    bookId: row['book_id'] as String,
    chapter: row['chapter'] as int,
    startVerse: row['start_verse'] as int,
    endVerse: row['end_verse'] as int,
    chapterVerseCount: row['chapter_verse_count'] as int,
    mode: row['mode'] as String,
    durationSeconds: row['duration_seconds'] as int,
    correctCount: row['correct_count'] as int,
    incorrectCount: row['incorrect_count'] as int,
    omittedCount: row['omitted_count'] as int,
    reorderedCount: row['reordered_count'] as int,
    accuracy: (row['accuracy'] as num).toDouble(),
    completedAt: DateTime.parse(row['completed_at'] as String).toLocal(),
  );

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  void close() => _database.close();
}

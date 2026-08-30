import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../../review/domain/ebbinghaus_models.dart';
import '../../review/domain/ebbinghaus_scheduler.dart';
import '../../quiz/domain/quiz_models.dart';
import '../../quiz/domain/quiz_model_settings.dart';
import '../../quiz/domain/quiz_question_source.dart';
import '../../quiz/domain/quiz_result.dart';
import '../../quiz/domain/quiz_scope.dart';
import '../../statistics/domain/achievement.dart';
import '../../statistics/domain/achievement_engine.dart';
import '../../statistics/domain/recitation_result.dart';
import '../domain/plan_models.dart';

final class SqlitePlanRepository {
  /// Bump this when stricter question validation makes cached unanswered
  /// questions unsuitable. Answered history remains intact for statistics.
  static const quizQuestionQualityVersion = 3;
  static const maxQuizQuestionsPerVerse = 5;
  static const _perPlanEbbinghausConsentMigrationKey =
      'per_plan_ebbinghaus_consent_v1';

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
        ebbinghaus_enabled INTEGER NOT NULL DEFAULT 0 CHECK(ebbinghaus_enabled IN (0, 1)),
        status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active', 'paused')),
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
        completed INTEGER NOT NULL DEFAULT 0 CHECK(completed IN (0, 1))
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS plan_task_block (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_task_id INTEGER NOT NULL REFERENCES plan_task(id) ON DELETE CASCADE,
        sort_order INTEGER NOT NULL CHECK(sort_order >= 0),
        book_id TEXT NOT NULL,
        start_chapter INTEGER NOT NULL CHECK(start_chapter > 0),
        start_verse INTEGER NOT NULL CHECK(start_verse > 0),
        end_chapter INTEGER NOT NULL CHECK(end_chapter >= start_chapter),
        end_verse INTEGER NOT NULL CHECK(end_verse > 0)
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
        character_count INTEGER NOT NULL DEFAULT 0,
        correct_count INTEGER NOT NULL,
        phonetic_correct_count INTEGER NOT NULL DEFAULT 0,
        incorrect_count INTEGER NOT NULL,
        omitted_count INTEGER NOT NULL,
        reordered_count INTEGER NOT NULL,
        accuracy REAL NOT NULL,
        plan_id INTEGER REFERENCES memorization_plan(id) ON DELETE SET NULL,
        started_at TEXT,
        completed_at TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS achievement_unlock (
        achievement_id TEXT PRIMARY KEY,
        unlocked_at TEXT NOT NULL,
        source TEXT NOT NULL,
        award_count INTEGER NOT NULL DEFAULT 1
      )
    ''');
    final achievementColumns = _database
        .select('PRAGMA table_info(achievement_unlock)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!achievementColumns.contains('award_count')) {
      _database.execute(
        'ALTER TABLE achievement_unlock ADD COLUMN award_count INTEGER NOT NULL DEFAULT 1',
      );
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS recitation_verse_metric (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recitation_result_id INTEGER NOT NULL
          REFERENCES recitation_result(id) ON DELETE CASCADE,
        plan_id INTEGER REFERENCES memorization_plan(id) ON DELETE SET NULL,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        accuracy REAL NOT NULL,
        duration_seconds INTEGER NOT NULL,
        started_at TEXT,
        completed_at TEXT NOT NULL
      )
    ''');
    _database.execute(
      '''CREATE INDEX IF NOT EXISTS idx_recitation_verse_metric_scope
      ON recitation_verse_metric(plan_id, translation_id, book_id, chapter, verse)''',
    );
    final metricColumns = _database
        .select('PRAGMA table_info(recitation_verse_metric)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!metricColumns.contains('character_count')) {
      _database.execute(
        'ALTER TABLE recitation_verse_metric ADD COLUMN character_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS app_setting (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL
      )
    ''');
    _database.execute(
      '''INSERT OR IGNORE INTO app_setting(setting_key, setting_value)
      VALUES ('first_opened_at', ?)''',
      [DateTime.now().toUtc().toIso8601String()],
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS quiz_question (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        start_offset INTEGER NOT NULL,
        end_offset INTEGER NOT NULL,
        word TEXT NOT NULL,
        part_of_speech TEXT NOT NULL,
        meaning TEXT NOT NULL,
        reference TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'local',
        quality_version INTEGER NOT NULL DEFAULT 1,
        answered INTEGER NOT NULL DEFAULT 0 CHECK(answered IN (0, 1)),
        is_correct INTEGER,
        answered_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    final quizQuestionColumns = _database
        .select('PRAGMA table_info(quiz_question)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!quizQuestionColumns.contains('quality_version')) {
      _database.execute(
        'ALTER TABLE quiz_question ADD COLUMN quality_version INTEGER NOT NULL DEFAULT 1',
      );
    }
    if (!quizQuestionColumns.contains('source')) {
      _database.execute(
        "ALTER TABLE quiz_question ADD COLUMN source TEXT NOT NULL DEFAULT 'local'",
      );
    }
    _database.execute('''CREATE INDEX IF NOT EXISTS idx_quiz_question_scope
      ON quiz_question(translation_id, book_id, chapter, verse, answered)''');
    _compactStoredQuizMeanings();
    _database.execute('''
      CREATE TABLE IF NOT EXISTS quiz_result (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id INTEGER NOT NULL
          REFERENCES quiz_question(id) ON DELETE CASCADE,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        correct INTEGER NOT NULL CHECK(correct IN (0, 1)),
        answered_at TEXT NOT NULL
      )
    ''');
    if (quizQuestionColumns.contains('verse_text')) {
      _removeStoredQuizVerseText();
    }
    _database.execute('''CREATE INDEX IF NOT EXISTS idx_quiz_question_scope
      ON quiz_question(translation_id, book_id, chapter, verse, answered)''');
    _database.execute('''UPDATE quiz_result
      SET question_id = (
        SELECT MIN(canonical.id)
        FROM quiz_question duplicate
        JOIN quiz_question canonical
          ON canonical.translation_id = duplicate.translation_id
          AND canonical.book_id = duplicate.book_id
          AND canonical.chapter = duplicate.chapter
          AND canonical.verse = duplicate.verse
          AND canonical.start_offset = duplicate.start_offset
          AND canonical.end_offset = duplicate.end_offset
        WHERE duplicate.id = quiz_result.question_id
      )''');
    _database.execute('''DELETE FROM quiz_question
      WHERE id NOT IN (
        SELECT MIN(id) FROM quiz_question
        GROUP BY translation_id, book_id, chapter, verse, start_offset, end_offset
      )''');
    _database.execute(
      '''CREATE UNIQUE INDEX IF NOT EXISTS idx_quiz_question_position
      ON quiz_question(translation_id, book_id, chapter, verse, start_offset, end_offset)''',
    );
    _migrateQuizResultsToHistorySchema();
    _database.execute('''CREATE INDEX IF NOT EXISTS idx_quiz_result_scope
      ON quiz_result(translation_id, book_id, chapter, verse)''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS quiz_bank_snapshot_staging (
        revision INTEGER NOT NULL,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        start_offset INTEGER NOT NULL,
        end_offset INTEGER NOT NULL,
        word TEXT NOT NULL,
        part_of_speech TEXT NOT NULL,
        meaning TEXT NOT NULL,
        reference TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'cloud',
        staged_at TEXT NOT NULL,
        UNIQUE(revision, translation_id, book_id, chapter, verse, start_offset, end_offset)
      )
    ''');
    final stagingColumns = _database
        .select('PRAGMA table_info(quiz_bank_snapshot_staging)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!stagingColumns.contains('source')) {
      _database.execute(
        "ALTER TABLE quiz_bank_snapshot_staging ADD COLUMN source TEXT NOT NULL DEFAULT 'cloud'",
      );
    }
    _database.execute('''
      CREATE TABLE IF NOT EXISTS plan_schedule_span (
        plan_id INTEGER PRIMARY KEY REFERENCES memorization_plan(id) ON DELETE CASCADE,
        days INTEGER NOT NULL CHECK(days > 365),
        end_date TEXT NOT NULL
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
        source_plan_id INTEGER REFERENCES memorization_plan(id) ON DELETE SET NULL,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        start_chapter INTEGER NOT NULL,
        start_verse INTEGER NOT NULL,
        end_chapter INTEGER NOT NULL,
        end_verse INTEGER NOT NULL,
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
    if (!columns.contains('status')) {
      _database.execute(
        "ALTER TABLE memorization_plan ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
      );
    }
    if (!columns.contains('ebbinghaus_enabled')) {
      _database.execute(
        'ALTER TABLE memorization_plan ADD COLUMN ebbinghaus_enabled INTEGER NOT NULL DEFAULT 0',
      );
    }
    final taskColumns = _database
        .select('PRAGMA table_info(plan_task)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!taskColumns.contains('book_id')) {
      _database.execute('ALTER TABLE plan_task ADD COLUMN book_id TEXT');
    }
    _migratePlanTasksForMultiplePassagesPerDay();
    _database.execute('''UPDATE plan_task
      SET book_id = (SELECT book_id FROM memorization_plan
        WHERE memorization_plan.id = plan_task.plan_id)
      WHERE book_id IS NULL''');
    _migratePlanTaskBlocks();
    _database.execute('''CREATE INDEX IF NOT EXISTS idx_plan_task_plan_day
      ON plan_task(plan_id, day_index)''');
    _database.execute(
      '''CREATE INDEX IF NOT EXISTS idx_plan_task_block_task_sort
      ON plan_task_block(plan_task_id, sort_order)''',
    );
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
    if (!resultColumns.contains('phonetic_correct_count')) {
      _database.execute(
        'ALTER TABLE recitation_result ADD COLUMN phonetic_correct_count INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!resultColumns.contains('plan_id')) {
      _database.execute(
        'ALTER TABLE recitation_result ADD COLUMN plan_id INTEGER',
      );
    }
    if (!resultColumns.contains('started_at')) {
      _database.execute(
        'ALTER TABLE recitation_result ADD COLUMN started_at TEXT',
      );
    }
    final cycleColumns = _database
        .select('PRAGMA table_info(ebbinghaus_cycle)')
        .map((row) => row['name'] as String)
        .toSet();
    for (final column in [
      'start_chapter',
      'start_verse',
      'end_chapter',
      'end_verse',
    ]) {
      if (!cycleColumns.contains(column)) {
        _database.execute(
          'ALTER TABLE ebbinghaus_cycle ADD COLUMN $column INTEGER NOT NULL DEFAULT 1',
        );
      }
    }
    if (!cycleColumns.contains('source_plan_id')) {
      _database.execute(
        'ALTER TABLE ebbinghaus_cycle ADD COLUMN source_plan_id INTEGER',
      );
      _database.execute('''UPDATE ebbinghaus_cycle SET source_plan_id =
        (SELECT plan_id FROM recitation_result WHERE id = source_result_id)''');
      _database.execute(
        "UPDATE ebbinghaus_cycle SET status = 'paused' WHERE source_plan_id IS NULL",
      );
      _database.execute('''UPDATE ebbinghaus_review SET status = 'cancelled'
        WHERE status = 'pending' AND cycle_id IN
          (SELECT id FROM ebbinghaus_cycle WHERE source_plan_id IS NULL)''');
    }
    _database.execute(
      '''UPDATE ebbinghaus_cycle SET
      start_chapter = (SELECT chapter FROM recitation_result WHERE id = source_result_id),
      start_verse = (SELECT start_verse FROM recitation_result WHERE id = source_result_id),
      end_chapter = (SELECT chapter FROM recitation_result WHERE id = source_result_id),
      end_verse = (SELECT end_verse FROM recitation_result WHERE id = source_result_id)''',
    );
    _migratePerPlanEbbinghausConsent();
    _database.execute('PRAGMA user_version = 8');
  }

  final Database _database;

  /// The old global setting was copied to every plan when per-plan reviews
  /// were introduced. That was not a deliberate choice for each plan, so a
  /// one-time migration resets those inherited flags and pauses their cycles.
  /// Users can opt in again from the individual plan editor.
  void _migratePerPlanEbbinghausConsent() {
    final migrated = _database.select(
      'SELECT 1 FROM app_setting WHERE setting_key = ?',
      [_perPlanEbbinghausConsentMigrationKey],
    );
    if (migrated.isNotEmpty) return;
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'UPDATE memorization_plan SET ebbinghaus_enabled = 0 '
        'WHERE ebbinghaus_enabled = 1',
      );
      _database.execute('''UPDATE ebbinghaus_cycle SET status = 'paused'
           WHERE status = 'active' AND source_plan_id IN
             (SELECT id FROM memorization_plan)''');
      _database.execute(
        'INSERT INTO app_setting(setting_key, setting_value) VALUES (?, ?)',
        [_perPlanEbbinghausConsentMigrationKey, '1'],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  static const _storedDayLimit = 365;

  int _storedDays(int days) => days > _storedDayLimit ? _storedDayLimit : days;

  DateTime _storedEndDate(DateTime start, int days) =>
      start.add(Duration(days: _storedDays(days) - 1));

  void _saveScheduleSpan(int planId, DateTime start, int days) {
    if (days <= _storedDayLimit) {
      _database.execute('DELETE FROM plan_schedule_span WHERE plan_id = ?', [
        planId,
      ]);
      return;
    }
    _database.execute(
      '''INSERT INTO plan_schedule_span(plan_id, days, end_date) VALUES (?, ?, ?)
      ON CONFLICT(plan_id) DO UPDATE SET days = excluded.days, end_date = excluded.end_date''',
      [planId, days, _date(start.add(Duration(days: days - 1)))],
    );
  }

  void _migratePlanTasksForMultiplePassagesPerDay() {
    final definition = _database.select(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'plan_task'",
    );
    if (definition.isEmpty ||
        !(definition.single['sql'] as String).contains(
          'UNIQUE(plan_id, day_index)',
        )) {
      return;
    }
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute('''
        CREATE TABLE plan_task_replacement (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          plan_id INTEGER NOT NULL REFERENCES memorization_plan(id) ON DELETE CASCADE,
          day_index INTEGER NOT NULL CHECK(day_index >= 0),
          due_date TEXT NOT NULL,
          book_id TEXT,
          start_chapter INTEGER NOT NULL CHECK(start_chapter > 0),
          start_verse INTEGER NOT NULL CHECK(start_verse > 0),
          end_chapter INTEGER NOT NULL CHECK(end_chapter >= start_chapter),
          end_verse INTEGER NOT NULL CHECK(end_verse > 0),
          completed INTEGER NOT NULL DEFAULT 0 CHECK(completed IN (0, 1))
        )
      ''');
      _database.execute('''
        INSERT INTO plan_task_replacement
          (id, plan_id, day_index, due_date, book_id, start_chapter,
           start_verse, end_chapter, end_verse, completed)
        SELECT id, plan_id, day_index, due_date, book_id, start_chapter,
               start_verse, end_chapter, end_verse, completed
        FROM plan_task
      ''');
      _database.execute('DROP TABLE plan_task');
      _database.execute(
        'ALTER TABLE plan_task_replacement RENAME TO plan_task',
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void _migratePlanTaskBlocks() {
    _database.execute('''
      INSERT INTO plan_task_block
        (plan_task_id, sort_order, book_id, start_chapter, start_verse,
         end_chapter, end_verse)
      SELECT t.id, 0, t.book_id, t.start_chapter, t.start_verse,
             t.end_chapter, t.end_verse
      FROM plan_task t
      WHERE NOT EXISTS (
        SELECT 1 FROM plan_task_block b WHERE b.plan_task_id = t.id
      )
    ''');
  }

  void _insertTaskBlocks(int taskId, NewPlanTask task, String fallbackBookId) {
    _insertBlocks(taskId, task.effectiveBlocks(fallbackBookId), fallbackBookId);
  }

  void _insertBlocks(
    int taskId,
    Iterable<NewPlanTaskBlock> blocks,
    String fallbackBookId, {
    int startSortOrder = 0,
  }) {
    var index = startSortOrder;
    for (final block in blocks) {
      _database.execute(
        '''INSERT INTO plan_task_block
        (plan_task_id, sort_order, book_id, start_chapter, start_verse,
         end_chapter, end_verse) VALUES (?, ?, ?, ?, ?, ?, ?)''',
        [
          taskId,
          index++,
          block.bookId ?? fallbackBookId,
          block.startChapter,
          block.startVerse,
          block.endChapter,
          block.endVerse,
        ],
      );
    }
  }

  Future<int> createPlan(NewMemorizationPlan plan) async {
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        '''INSERT INTO memorization_plan
        (title, translation_id, book_id, start_chapter, end_chapter, days,
         start_date, end_date, source_kind, source_url, external_id, revision,
         content_locked, ebbinghaus_enabled, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          plan.title,
          plan.translationId,
          plan.bookId,
          plan.startChapter,
          plan.endChapter,
          _storedDays(plan.days),
          _date(plan.startDate),
          _date(_storedEndDate(plan.startDate, plan.days)),
          plan.sourceKind.name,
          plan.sourceUrl,
          plan.externalId,
          plan.revision,
          plan.contentLocked ? 1 : 0,
          plan.ebbinghausEnabled ? 1 : 0,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      final id = _database.lastInsertRowId;
      _saveScheduleSpan(id, plan.startDate, plan.days);
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
        _insertTaskBlocks(_database.lastInsertRowId, task, plan.bookId);
      }
      _database.execute('COMMIT');
      return id;
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<MemorizationPlan>> listPlans() async {
    return _database
        .select('''
      SELECT p.*, COALESCE(s.days, p.days) AS effective_days,
        COALESCE(s.end_date, p.end_date) AS effective_end_date,
        COUNT(t.id) AS total_tasks,
        COALESCE(SUM(t.completed), 0) AS completed_tasks,
        (SELECT COUNT(*) FROM recitation_result r WHERE r.plan_id = p.id) AS recitation_sessions,
        COALESCE((SELECT AVG(r.accuracy) FROM recitation_result r WHERE r.plan_id = p.id), 0) AS average_accuracy,
        COALESCE((SELECT SUM(r.duration_seconds) FROM recitation_result r WHERE r.plan_id = p.id), 0) AS total_recitation_seconds
      FROM memorization_plan p
      LEFT JOIN plan_schedule_span s ON s.plan_id = p.id
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

  Future<DateTime> getFirstOpenedAt() async => DateTime.parse(
    await getSetting(
      'first_opened_at',
      DateTime.now().toUtc().toIso8601String(),
    ),
  ).toLocal();

  Future<void> setSetting(String key, String value) async {
    _database.execute(
      '''
      INSERT INTO app_setting(setting_key, setting_value) VALUES (?, ?)
      ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value
    ''',
      [key, value],
    );
  }

  /// Quiz model settings live in app_setting and model answering is opt-in.
  Future<QuizModelSettings> getQuizModelSettings() async {
    final baseUrl = await getSetting(
      'quiz_model_url',
      QuizModelSettings.defaultBaseUrl,
    );
    final model = await getSetting(
      'quiz_model_name',
      QuizModelSettings.defaultModel,
    );
    final apiKey = await getSetting('quiz_model_api_key', '');
    final modelAnsweringEnabled =
        await getSetting('quiz_model_answering_enabled', 'false') == 'true';
    return QuizModelSettings(
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
      modelAnsweringEnabled: modelAnsweringEnabled,
    );
  }

  Future<void> saveQuizModelSettings(QuizModelSettings settings) async {
    await setSetting('quiz_model_url', settings.baseUrl.trim());
    await setSetting('quiz_model_name', settings.model.trim());
    await setSetting('quiz_model_api_key', settings.apiKey);
    await setSetting(
      'quiz_model_answering_enabled',
      settings.modelAnsweringEnabled.toString(),
    );
  }

  Future<void> clearQuizModelApiKey() async {
    await setSetting('quiz_model_api_key', '');
  }

  /// Lists unanswered questions for the exact scope in canonical order.
  Future<List<PendingQuizQuestion>> listPendingQuizQuestions(
    QuizScope scope,
  ) async {
    final rows = _database.select(
      '''
      SELECT id, translation_id, book_id, chapter, verse, start_offset,
        end_offset, word, part_of_speech, meaning, reference, source
      FROM quiz_question
      WHERE translation_id = ? AND book_id = ?
        AND ((chapter > ? OR (chapter = ? AND verse >= ?))
          AND (chapter < ? OR (chapter = ? AND verse <= ?)))
        AND answered = 0 AND quality_version = ?
      ORDER BY chapter, verse, start_offset, id
    ''',
      [
        scope.translationId,
        scope.bookId,
        scope.startChapter,
        scope.startChapter,
        scope.startVerse,
        scope.endChapter,
        scope.endChapter,
        scope.endVerse,
        quizQuestionQualityVersion,
      ],
    );
    return rows.map(_pendingQuestionFromRow).toList(growable: false);
  }

  /// Returns at most one unanswered question per verse for a practice run.
  /// A shared/imported bank may contain several questions for the same verse;
  /// presenting all of them together would turn one verse into a burst of
  /// repeated questions. Pick one locally, while leaving the other questions
  /// available for a later practice run.
  Future<List<PendingQuizQuestion>> listQuizQuestionsForPractice(
    QuizScope scope, {
    QuizQuestionSource? preferredSource,
  }) async {
    final pending = await listPendingQuizQuestions(scope);
    final byVerse = <(int chapter, int verse), List<PendingQuizQuestion>>{};
    for (final question in pending) {
      byVerse
          .putIfAbsent((question.chapter, question.verse), () => [])
          .add(question);
    }
    final random = math.Random();
    final selected = <PendingQuizQuestion>[
      for (final questions in byVerse.values)
        _selectPracticeQuestion(
          questions,
          random,
          preferredSource: preferredSource,
        ),
    ];
    // Pick one candidate at random for each verse, then keep the passages in
    // scripture order so a multi-chapter practice remains easy to follow.
    selected.sort((a, b) {
      final chapter = a.chapter.compareTo(b.chapter);
      if (chapter != 0) return chapter;
      final verse = a.verse.compareTo(b.verse);
      if (verse != 0) return verse;
      return a.start.compareTo(b.start);
    });
    return selected;
  }

  PendingQuizQuestion _selectPracticeQuestion(
    List<PendingQuizQuestion> questions,
    math.Random random, {
    QuizQuestionSource? preferredSource,
  }) {
    final preferredQuestions = preferredSource == null
        ? const <PendingQuizQuestion>[]
        : questions
              .where((question) => question.source == preferredSource)
              .toList(growable: false);
    final candidates = preferredQuestions.isEmpty
        ? questions
        : preferredQuestions;
    return candidates[random.nextInt(candidates.length)];
  }

  /// Selects a random local-bank practice set and reopens the selected
  /// questions for a new attempt. This intentionally includes previously
  /// answered questions so “随机答题” can draw from the entire local bank;
  /// each new submission is recorded as a new quiz result.
  Future<List<PendingQuizQuestion>> listRandomQuizQuestionsForPractice(
    int count, {
    QuizQuestionSource? preferredSource,
  }) async {
    if (count <= 0) return const [];
    final orderBy = preferredSource == null
        ? 'RANDOM()'
        : 'CASE WHEN source = ? THEN 0 ELSE 1 END, RANDOM()';
    final arguments = <Object?>[
      quizQuestionQualityVersion,
      if (preferredSource != null) preferredSource.storageValue,
      count,
    ];
    _database.execute('BEGIN IMMEDIATE');
    try {
      final rows = _database.select(
        '''SELECT id, translation_id, book_id, chapter, verse, start_offset,
          end_offset, word, part_of_speech, meaning, reference, source
        FROM quiz_question WHERE quality_version = ?
        ORDER BY $orderBy LIMIT ?''',
        arguments,
      );
      for (final row in rows) {
        _database.execute(
          '''UPDATE quiz_question
          SET answered = 0, is_correct = NULL, answered_at = NULL
          WHERE id = ?''',
          [row['id']],
        );
      }
      _database.execute('COMMIT');
      return rows.map(_pendingQuestionFromRow).toList(growable: false);
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Selects a random local-bank practice set constrained to the supplied
  /// whole-chapter ranges. Completed questions are reopened for the new run,
  /// just like the unrestricted random-practice entry point.
  Future<List<PendingQuizQuestion>> listRandomQuizQuestionsForPracticeInScopes(
    Iterable<QuizScope> requestedScopes,
    int count, {
    QuizQuestionSource? preferredSource,
  }) async {
    final scopes = {...requestedScopes}.toList(growable: false);
    if (count <= 0 || scopes.isEmpty) return const [];
    final conditions = <String>[];
    final arguments = <Object?>[quizQuestionQualityVersion];
    for (final scope in scopes) {
      conditions.add(
        '(translation_id = ? AND book_id = ? AND chapter BETWEEN ? AND ?)',
      );
      arguments.addAll([
        scope.translationId,
        scope.bookId,
        scope.startChapter,
        scope.endChapter,
      ]);
    }
    final orderBy = preferredSource == null
        ? 'RANDOM()'
        : 'CASE WHEN source = ? THEN 0 ELSE 1 END, RANDOM()';
    if (preferredSource != null) {
      arguments.add(preferredSource.storageValue);
    }
    arguments.add(count);
    _database.execute('BEGIN IMMEDIATE');
    try {
      final rows = _database.select(
        '''SELECT id, translation_id, book_id, chapter, verse, start_offset,
          end_offset, word, part_of_speech, meaning, reference, source
        FROM quiz_question
        WHERE quality_version = ? AND (${conditions.join(' OR ')})
        ORDER BY $orderBy LIMIT ?''',
        arguments,
      );
      for (final row in rows) {
        _database.execute(
          '''UPDATE quiz_question
          SET answered = 0, is_correct = NULL, answered_at = NULL
          WHERE id = ?''',
          [row['id']],
        );
      }
      _database.execute('COMMIT');
      return rows.map(_pendingQuestionFromRow).toList(growable: false);
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// All current-quality questions, without answer history. Used only for
  /// personal export and cloud-bank import/sync; credentials and statistics
  /// never leave the device.
  Future<List<QuizBankQuestion>> listQuizBankQuestions() async {
    final rows = _database.select(
      '''SELECT translation_id, book_id, chapter, verse, start_offset,
        end_offset, word, part_of_speech, meaning, reference, source
      FROM quiz_question WHERE quality_version = ?
      ORDER BY translation_id, book_id, chapter, verse, start_offset, end_offset''',
      [quizQuestionQualityVersion],
    );
    return rows
        .map(
          (row) => QuizBankQuestion(
            reference: row['reference'] as String,
            translationId: row['translation_id'] as String,
            bookId: row['book_id'] as String,
            chapter: row['chapter'] as int,
            verse: row['verse'] as int,
            start: row['start_offset'] as int,
            end: row['end_offset'] as int,
            word: row['word'] as String,
            partOfSpeech: row['part_of_speech'] as String,
            meaning: row['meaning'] as String,
            source: QuizQuestionSourcePresentation.fromStorage(row['source']),
          ),
        )
        .toList(growable: false);
  }

  /// Number of current-quality questions stored locally, including questions
  /// already answered. This is the personal-bank size shown in “我的”.
  Future<int> countQuizBankQuestions() async =>
      _database.select(
            'SELECT COUNT(*) AS count FROM quiz_question '
            'WHERE quality_version = ?',
            [quizQuestionQualityVersion],
          ).single['count']
          as int;

  /// Verses in the scope that still need a generated question, i.e. verses
  /// without any unanswered question.
  Future<List<({int chapter, int verse})>> missingQuizVerses(
    QuizScope scope,
  ) async {
    final required = <({int chapter, int verse})>[];
    final verseCounts = _chapterVerseCounts(scope);
    for (
      var chapter = scope.startChapter;
      chapter <= scope.endChapter;
      chapter++
    ) {
      final count = verseCounts[chapter] ?? scope.endVerse;
      final startVerse = chapter == scope.startChapter ? scope.startVerse : 1;
      final endVerse = chapter == scope.endChapter ? scope.endVerse : count;
      for (var verse = startVerse; verse <= endVerse; verse++) {
        required.add((chapter: chapter, verse: verse));
      }
    }
    final missing = <({int chapter, int verse})>[];
    for (final target in required) {
      final pending = await hasPendingQuizQuestion(
        translationId: scope.translationId,
        bookId: scope.bookId,
        chapter: target.chapter,
        verse: target.verse,
      );
      if (!pending &&
          !await hasQuizQuestionBankCapacity(
            translationId: scope.translationId,
            bookId: scope.bookId,
            chapter: target.chapter,
            verse: target.verse,
          )) {
        missing.add(target);
      }
    }
    return missing;
  }

  Map<int, int> _chapterVerseCounts(QuizScope scope) {
    final counts = <int, int>{};
    if (scope.startChapter == scope.endChapter) return counts;
    final rows = _database.select(
      '''
      SELECT chapter, COUNT(*) AS verse_count
      FROM quiz_question
      WHERE translation_id = ? AND book_id = ?
        AND chapter >= ? AND chapter <= ? AND quality_version = ?
      GROUP BY chapter
    ''',
      [
        scope.translationId,
        scope.bookId,
        scope.startChapter,
        scope.endChapter,
        quizQuestionQualityVersion,
      ],
    );
    for (final row in rows) {
      counts[row['chapter'] as int] = row['verse_count'] as int;
    }
    return counts;
  }

  Future<bool> hasPendingQuizQuestion({
    required String translationId,
    required String bookId,
    required int chapter,
    required int verse,
  }) async {
    final rows = _database.select(
      '''
      SELECT 1 FROM quiz_question
      WHERE translation_id = ? AND book_id = ? AND chapter = ? AND verse = ?
        AND answered = 0 AND quality_version = ?
      LIMIT 1
    ''',
      [translationId, bookId, chapter, verse, quizQuestionQualityVersion],
    );
    return rows.isNotEmpty;
  }

  Future<bool> hasQuizQuestionBankCapacity({
    required String translationId,
    required String bookId,
    required int chapter,
    required int verse,
  }) async {
    final count =
        _database
                .select(
                  '''SELECT COUNT(*) AS count FROM quiz_question
          WHERE translation_id = ? AND book_id = ? AND chapter = ? AND verse = ?
            AND quality_version = ?''',
                  [
                    translationId,
                    bookId,
                    chapter,
                    verse,
                    quizQuestionQualityVersion,
                  ],
                )
                .single['count']
            as int;
    return count >= maxQuizQuestionsPerVerse;
  }

  Future<bool> requeueRandomQuizQuestion({
    required String translationId,
    required String bookId,
    required int chapter,
    required int verse,
    QuizQuestionSource? source,
  }) async {
    final sourceClause = source == null ? '' : ' AND source = ?';
    final rows = _database.select(
      '''SELECT id FROM quiz_question
      WHERE translation_id = ? AND book_id = ? AND chapter = ? AND verse = ?
        AND quality_version = ?$sourceClause
      ORDER BY RANDOM() LIMIT 1''',
      [
        translationId,
        bookId,
        chapter,
        verse,
        quizQuestionQualityVersion,
        if (source != null) source.storageValue,
      ],
    );
    if (rows.isEmpty) return false;
    _database.execute(
      '''UPDATE quiz_question
      SET answered = 0, is_correct = NULL, answered_at = NULL
      WHERE id = ?''',
      [rows.single['id']],
    );
    return true;
  }

  Future<void> saveQuizQuestions(
    List<ValidatedQuizQuestion> questions, {
    bool replaceExisting = false,
  }) async {
    if (questions.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final insertSql = replaceExisting
        ? '''
          INSERT INTO quiz_question
          (translation_id, book_id, chapter, verse, start_offset, end_offset,
           word, part_of_speech, meaning, reference,
           source, quality_version, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(translation_id, book_id, chapter, verse, start_offset,
                      end_offset)
          DO UPDATE SET word = excluded.word,
                        part_of_speech = excluded.part_of_speech,
                        meaning = excluded.meaning,
                        reference = excluded.reference,
                        source = excluded.source,
                        quality_version = excluded.quality_version,
                        created_at = excluded.created_at
        '''
        : '''
          INSERT OR IGNORE INTO quiz_question
          (translation_id, book_id, chapter, verse, start_offset, end_offset,
           word, part_of_speech, meaning, reference,
           source, quality_version, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''';
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final question in questions) {
        _database.execute(insertSql, [
          question.translationId,
          question.bookId,
          question.chapter,
          question.verse,
          question.start,
          question.end,
          question.word,
          question.partOfSpeech,
          compactQuizMeaning(question.word, question.meaning),
          question.reference,
          question.source.storageValue,
          quizQuestionQualityVersion,
          now,
        ]);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Adds portable questions without changing the answer state of a matching
  /// local question. New questions start unanswered so they can be practised;
  /// existing history and accuracy remain strictly local, while bank-managed
  /// fields such as the meaning are refreshed from the newest bank.
  Future<QuizBankImportResult> importQuizBankQuestions(
    List<ValidatedQuizQuestion> questions,
  ) async {
    if (questions.isEmpty) return const QuizBankImportResult();
    var imported = 0;
    var updated = 0;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final question in questions) {
        final meaning = compactQuizMeaning(question.word, question.meaning);
        final existing = _database.select(
          '''SELECT id, word, part_of_speech, meaning, reference,
                    quality_version, source
             FROM quiz_question
             WHERE translation_id = ? AND book_id = ? AND chapter = ?
               AND verse = ? AND start_offset = ? AND end_offset = ?''',
          [
            question.translationId,
            question.bookId,
            question.chapter,
            question.verse,
            question.start,
            question.end,
          ],
        );
        if (existing.isEmpty) {
          _database.execute(
            '''
            INSERT INTO quiz_question
            (translation_id, book_id, chapter, verse, start_offset, end_offset,
             word, part_of_speech, meaning, reference,
             source, quality_version, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ''',
            [
              question.translationId,
              question.bookId,
              question.chapter,
              question.verse,
              question.start,
              question.end,
              question.word,
              question.partOfSpeech,
              meaning,
              question.reference,
              question.source.storageValue,
              quizQuestionQualityVersion,
              now,
            ],
          );
          imported++;
          continue;
        }
        final row = existing.single;
        final changed =
            row['word'] != question.word ||
            row['part_of_speech'] != question.partOfSpeech ||
            row['meaning'] != meaning ||
            row['reference'] != question.reference ||
            row['source'] != question.source.storageValue ||
            row['quality_version'] != quizQuestionQualityVersion;
        if (!changed) continue;
        _database.execute(
          '''UPDATE quiz_question
             SET word = ?, part_of_speech = ?, meaning = ?, reference = ?,
                 source = ?, quality_version = ?
             WHERE id = ?''',
          [
            question.word,
            question.partOfSpeech,
            meaning,
            question.reference,
            question.source.storageValue,
            quizQuestionQualityVersion,
            row['id'],
          ],
        );
        updated++;
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
    return QuizBankImportResult(
      imported: imported,
      duplicates: questions.length - imported,
      updated: updated,
    );
  }

  /// Adds a verified shard to an inactive replacement snapshot. This never
  /// changes questions currently available for practice.
  Future<void> stageQuizBankSnapshot(
    int revision,
    List<ValidatedQuizQuestion> questions,
  ) async {
    if (revision < 1) throw ArgumentError.value(revision, 'revision');
    if (questions.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final question in questions) {
        _database.execute(
          '''
          INSERT INTO quiz_bank_snapshot_staging
          (revision, translation_id, book_id, chapter, verse, start_offset,
           end_offset, word, part_of_speech, meaning, reference, source,
           staged_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(revision, translation_id, book_id, chapter, verse,
                      start_offset, end_offset)
          DO UPDATE SET word = excluded.word,
                        part_of_speech = excluded.part_of_speech,
                        meaning = excluded.meaning,
                        reference = excluded.reference,
                        source = excluded.source,
                        staged_at = excluded.staged_at
        ''',
          [
            revision,
            question.translationId,
            question.bookId,
            question.chapter,
            question.verse,
            question.start,
            question.end,
            question.word,
            question.partOfSpeech,
            compactQuizMeaning(question.word, question.meaning),
            question.reference,
            question.source.storageValue,
            now,
          ],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Activates one completely staged quality-v3 snapshot. Historical results
  /// retain their own scope and correctness fields after their obsolete local
  /// question ids are detached.
  Future<void> activateStagedQuizBankSnapshot(int revision) async {
    if (revision < 1) throw ArgumentError.value(revision, 'revision');
    _database.execute('BEGIN IMMEDIATE');
    try {
      final count =
          _database.select(
                'SELECT COUNT(*) AS count FROM quiz_bank_snapshot_staging WHERE revision = ?',
                [revision],
              ).single['count']
              as int;
      if (count == 0) throw StateError('没有可激活的题库快照');
      _database.execute(
        'UPDATE quiz_result SET question_id = NULL WHERE question_id IS NOT NULL',
      );
      _database.execute('DELETE FROM quiz_question');
      _database.execute(
        '''
        INSERT INTO quiz_question
         (translation_id, book_id, chapter, verse, start_offset, end_offset,
         word, part_of_speech, meaning, reference, source, quality_version,
         answered,
         created_at)
        SELECT translation_id, book_id, chapter, verse, start_offset, end_offset,
          word, part_of_speech, meaning, reference, source, ?, 0, staged_at
        FROM quiz_bank_snapshot_staging WHERE revision = ?
        ORDER BY translation_id, book_id, chapter, verse, start_offset, end_offset
      ''',
        [quizQuestionQualityVersion, revision],
      );
      _database.execute(
        'DELETE FROM quiz_bank_snapshot_staging WHERE revision = ?',
        [revision],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> discardStagedQuizBankSnapshot(int revision) async {
    _database.execute(
      'DELETE FROM quiz_bank_snapshot_staging WHERE revision = ?',
      [revision],
    );
  }

  /// Completes one pending question and records exactly one quiz_result in a
  /// transaction, updating the current and maximum correct-streak settings.
  Future<QuizCompletion> completeQuizQuestion({
    required int questionId,
    required bool correct,
    required DateTime answeredAt,
  }) async {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final question = _database.select(
        'SELECT * FROM quiz_question WHERE id = ?',
        [questionId],
      );
      if (question.isEmpty) {
        throw StateError('答题题目不存在');
      }
      final row = question.single;
      if ((row['answered'] as int) == 1) {
        final totalAnswered = await _quizTotalAnswered();
        final totalCorrect = await _quizTotalCorrect();
        final current =
            int.tryParse(await _settingRaw('current_quiz_correct_streak')) ?? 0;
        final max =
            int.tryParse(await _settingRaw('max_quiz_correct_streak')) ?? 0;
        _database.execute('COMMIT');
        return QuizCompletion(
          totalAnswered: totalAnswered,
          totalCorrect: totalCorrect,
          currentCorrectStreak: current,
          maxCorrectStreak: max,
        );
      }
      _database.execute(
        '''
        INSERT INTO quiz_result
        (question_id, translation_id, book_id, chapter, verse, correct, answered_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          questionId,
          row['translation_id'],
          row['book_id'],
          row['chapter'],
          row['verse'],
          correct ? 1 : 0,
          answeredAt.toUtc().toIso8601String(),
        ],
      );
      _database.execute(
        '''
        UPDATE quiz_question SET answered = 1, is_correct = ?, answered_at = ?
        WHERE id = ?
      ''',
        [correct ? 1 : 0, answeredAt.toUtc().toIso8601String(), questionId],
      );
      final current =
          int.tryParse(await _settingRaw('current_quiz_correct_streak')) ?? 0;
      final max =
          int.tryParse(await _settingRaw('max_quiz_correct_streak')) ?? 0;
      final nextCurrent = correct ? current + 1 : 0;
      final nextMax = max > nextCurrent ? max : nextCurrent;
      await _setSettingRaw('current_quiz_correct_streak', '$nextCurrent');
      await _setSettingRaw('max_quiz_correct_streak', '$nextMax');
      _database.execute('COMMIT');
      return QuizCompletion(
        totalAnswered: (await _quizTotalAnswered()),
        totalCorrect: (await _quizTotalCorrect()),
        currentCorrectStreak: nextCurrent,
        maxCorrectStreak: nextMax,
      );
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<QuizSummary> getQuizSummary() async {
    final totalAnswered = await _quizTotalAnswered();
    final totalCorrect = await _quizTotalCorrect();
    final current =
        int.tryParse(await _settingRaw('current_quiz_correct_streak')) ?? 0;
    final max = int.tryParse(await _settingRaw('max_quiz_correct_streak')) ?? 0;
    return QuizSummary(
      totalAnswered: totalAnswered,
      totalCorrect: totalCorrect,
      currentCorrectStreak: current,
      maxCorrectStreak: max,
    );
  }

  /// Quiz aggregates restricted to one optional scope.  With no filter it
  /// returns the global summary; with a book, chapter or verse it returns a
  /// range metric for that exact scope.
  Future<QuizRangeMetric> getQuizMetric({
    String? translationId,
    String? bookId,
    int? chapter,
    int? verse,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (translationId != null) {
      clauses.add('translation_id = ?');
      args.add(translationId);
    }
    if (bookId != null) {
      clauses.add('book_id = ?');
      args.add(bookId);
    }
    if (chapter != null) {
      clauses.add('chapter = ?');
      args.add(chapter);
    }
    if (verse != null) {
      clauses.add('verse = ?');
      args.add(verse);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = _database.select(
      'SELECT COUNT(*) AS answered, '
      'COALESCE(SUM(correct), 0) AS correct FROM quiz_result $where',
      args,
    );
    final row = rows.single;
    return QuizRangeMetric(
      answered: row['answered'] as int,
      correct: (row['correct'] as num).toInt(),
    );
  }

  Future<List<QuizRangeMetric>> getQuizRangeMetrics({
    required String translationId,
    required String bookId,
    int? chapter,
  }) async {
    final rows = _database.select(
      '''
      SELECT chapter, verse, COUNT(*) AS answered,
        COALESCE(SUM(correct), 0) AS correct
      FROM quiz_result
      WHERE translation_id = ? AND book_id = ?
        ${chapter == null ? '' : 'AND chapter = ?'}
      GROUP BY chapter, verse
      ORDER BY chapter, verse
    ''',
      chapter == null
          ? [translationId, bookId]
          : [translationId, bookId, chapter],
    );
    return [
      for (final row in rows)
        QuizRangeMetric(
          answered: row['answered'] as int,
          correct: (row['correct'] as num).toInt(),
        ),
    ];
  }

  /// Returns answered-question aggregates with their verse coordinates.
  Future<List<QuizVerseMetric>> listQuizVerseMetrics({
    String? translationId,
    String? bookId,
    int? chapter,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (translationId != null) {
      clauses.add('translation_id = ?');
      args.add(translationId);
    }
    if (bookId != null) {
      clauses.add('book_id = ?');
      args.add(bookId);
    }
    if (chapter != null) {
      clauses.add('chapter = ?');
      args.add(chapter);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = _database.select('''
      SELECT translation_id, book_id, chapter, verse, COUNT(*) AS answered,
        COALESCE(SUM(correct), 0) AS correct
      FROM quiz_result $where
      GROUP BY translation_id, book_id, chapter, verse
      ORDER BY translation_id, book_id, chapter, verse
    ''', args);
    return [
      for (final row in rows)
        QuizVerseMetric(
          translationId: row['translation_id'] as String,
          bookId: row['book_id'] as String,
          chapter: row['chapter'] as int,
          verse: row['verse'] as int,
          answered: row['answered'] as int,
          correct: (row['correct'] as num).toInt(),
        ),
    ];
  }

  Future<String> _settingRaw(String key) async {
    final rows = _database.select(
      'SELECT setting_value FROM app_setting WHERE setting_key = ?',
      [key],
    );
    return rows.isEmpty ? '0' : rows.single['setting_value'] as String;
  }

  Future<void> _setSettingRaw(String key, String value) async {
    _database.execute(
      '''
      INSERT INTO app_setting(setting_key, setting_value) VALUES (?, ?)
      ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value
    ''',
      [key, value],
    );
  }

  Future<int> _quizTotalAnswered() async {
    final row = _database
        .select('SELECT COUNT(*) AS count FROM quiz_result')
        .single;
    return row['count'] as int;
  }

  Future<int> _quizTotalCorrect() async {
    final row = _database
        .select('SELECT COUNT(*) AS count FROM quiz_result WHERE correct = 1')
        .single;
    return row['count'] as int;
  }

  PendingQuizQuestion _pendingQuestionFromRow(Row row) => PendingQuizQuestion(
    id: row['id'] as int,
    translationId: row['translation_id'] as String,
    bookId: row['book_id'] as String,
    chapter: row['chapter'] as int,
    verse: row['verse'] as int,
    start: row['start_offset'] as int,
    end: row['end_offset'] as int,
    word: row['word'] as String,
    partOfSpeech: row['part_of_speech'] as String,
    meaning: row['meaning'] as String,
    reference: row['reference'] as String,
    source: QuizQuestionSourcePresentation.fromStorage(row['source']),
  );

  /// quiz_result used to cascade-delete history with quiz_question. A replace
  /// snapshot intentionally removes every active question, so history must be
  /// independent while retaining its verse-level fields for all statistics.
  void _migrateQuizResultsToHistorySchema() {
    final columns = _database.select('PRAGMA table_info(quiz_result)');
    final questionId = columns.singleWhere(
      (row) => row['name'] == 'question_id',
    );
    final hasForeignKey = _database
        .select('PRAGMA foreign_key_list(quiz_result)')
        .isNotEmpty;
    if (questionId['notnull'] == 0 && !hasForeignKey) return;
    _database.execute('PRAGMA foreign_keys = OFF');
    try {
      _database.execute('''
        CREATE TABLE quiz_result_history_migration (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          question_id INTEGER,
          translation_id TEXT NOT NULL,
          book_id TEXT NOT NULL,
          chapter INTEGER NOT NULL,
          verse INTEGER NOT NULL,
          correct INTEGER NOT NULL CHECK(correct IN (0, 1)),
          answered_at TEXT NOT NULL
        )
      ''');
      _database.execute('''
        INSERT INTO quiz_result_history_migration
        (id, question_id, translation_id, book_id, chapter, verse, correct, answered_at)
        SELECT id, question_id, translation_id, book_id, chapter, verse, correct, answered_at
        FROM quiz_result
      ''');
      _database.execute('DROP TABLE quiz_result');
      _database.execute(
        'ALTER TABLE quiz_result_history_migration RENAME TO quiz_result',
      );
    } finally {
      _database.execute('PRAGMA foreign_keys = ON');
    }
  }

  /// Older releases duplicated the full verse in every question. Rebuild the
  /// table instead of merely clearing the column so existing devices reclaim
  /// that storage as well. Question ids stay unchanged, preserving results.
  void _removeStoredQuizVerseText() {
    _database.execute('PRAGMA foreign_keys = OFF');
    try {
      _database.execute('''
        CREATE TABLE quiz_question_without_verse_text (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          translation_id TEXT NOT NULL,
          book_id TEXT NOT NULL,
          chapter INTEGER NOT NULL,
          verse INTEGER NOT NULL,
          start_offset INTEGER NOT NULL,
          end_offset INTEGER NOT NULL,
          word TEXT NOT NULL,
          part_of_speech TEXT NOT NULL,
          meaning TEXT NOT NULL,
          reference TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'local',
          quality_version INTEGER NOT NULL DEFAULT 1,
          answered INTEGER NOT NULL DEFAULT 0 CHECK(answered IN (0, 1)),
          is_correct INTEGER,
          answered_at TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      _database.execute('''
        INSERT INTO quiz_question_without_verse_text
        (id, translation_id, book_id, chapter, verse, start_offset, end_offset,
         word, part_of_speech, meaning, reference, quality_version, answered,
         source, is_correct, answered_at, created_at)
        SELECT id, translation_id, book_id, chapter, verse, start_offset, end_offset,
          word, part_of_speech, meaning, reference, quality_version, answered,
          source, is_correct, answered_at, created_at
        FROM quiz_question
      ''');
      _database.execute('DROP TABLE quiz_question');
      _database.execute(
        'ALTER TABLE quiz_question_without_verse_text RENAME TO quiz_question',
      );
    } finally {
      _database.execute('PRAGMA foreign_keys = ON');
    }
  }

  void _compactStoredQuizMeanings() {
    final rows = _database.select(
      'SELECT id, word, meaning FROM quiz_question',
    );
    for (final row in rows) {
      final compact = compactQuizMeaning(
        row['word'] as String,
        row['meaning'] as String,
      );
      if (compact != row['meaning']) {
        _database.execute('UPDATE quiz_question SET meaning = ? WHERE id = ?', [
          compact,
          row['id'],
        ]);
      }
    }
  }

  Future<MemorizationPlan?> findPlanBySource(
    String sourceUrl,
    String externalId,
  ) async {
    final rows = _database.select(
      '''
      SELECT p.*, COALESCE(s.days, p.days) AS effective_days,
        COALESCE(s.end_date, p.end_date) AS effective_end_date,
        COUNT(t.id) AS total_tasks,
        COALESCE(SUM(t.completed), 0) AS completed_tasks
      FROM memorization_plan p
      LEFT JOIN plan_schedule_span s ON s.plan_id = p.id
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
    return _tasksFromRows(
      _database.select(
        'SELECT * FROM plan_task WHERE plan_id = ? ORDER BY day_index, id',
        [planId],
      ),
    );
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
        _insertTaskBlocks(_database.lastInsertRowId, task, plan.bookId);
      }
      final days = plan.days + passages.length;
      _database.execute(
        'UPDATE memorization_plan SET days = ?, end_date = ? WHERE id = ?',
        [
          _storedDays(days),
          _date(_storedEndDate(plan.startDate, days)),
          plan.id,
        ],
      );
      _saveScheduleSpan(plan.id, plan.startDate, days);
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
    return _tasksFromRows(
      _database.select(
        includeCompleted
            ? '''SELECT t.* FROM plan_task t
                JOIN memorization_plan p ON p.id = t.plan_id
                WHERE p.status = 'active' AND ((t.completed = 0 AND t.due_date <= ?)
                   OR (t.completed = 1 AND t.due_date = ?))
                ORDER BY completed, due_date, id'''
            : '''SELECT t.* FROM plan_task t
                JOIN memorization_plan p ON p.id = t.plan_id
                WHERE p.status = 'active' AND t.completed = 0 AND t.due_date <= ?
                ORDER BY due_date, id''',
        includeCompleted ? [value, value] : [value],
      ),
    );
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
        external_id = ?, revision = ?, content_locked = ?, ebbinghaus_enabled = ? WHERE id = ?''',
        [
          plan.title,
          plan.translationId,
          plan.bookId,
          plan.startChapter,
          plan.endChapter,
          _storedDays(plan.days),
          _date(plan.startDate),
          _date(_storedEndDate(plan.startDate, plan.days)),
          plan.sourceKind.name,
          plan.sourceUrl,
          plan.externalId,
          plan.revision,
          plan.contentLocked ? 1 : 0,
          plan.ebbinghausEnabled ? 1 : 0,
          planId,
        ],
      );
      if (!plan.ebbinghausEnabled) {
        _database.execute(
          "UPDATE ebbinghaus_cycle SET status = 'paused' "
          "WHERE source_plan_id = ? AND status = 'active'",
          [planId],
        );
      }
      _saveScheduleSpan(planId, plan.startDate, plan.days);
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
        _insertTaskBlocks(_database.lastInsertRowId, task, plan.bookId);
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

  Future<void> pausePlan(int planId) async {
    _database.execute(
      "UPDATE memorization_plan SET status = 'paused' WHERE id = ?",
      [planId],
    );
    _database.execute(
      '''
      UPDATE ebbinghaus_cycle SET status = 'paused'
      WHERE status = 'active' AND source_plan_id = ?
    ''',
      [planId],
    );
  }

  Future<void> resumePlan(int planId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _database.execute('BEGIN IMMEDIATE');
    try {
      final unfinished = _database.select(
        '''SELECT day_index FROM plan_task
        WHERE plan_id = ? AND completed = 0
        ORDER BY day_index, id LIMIT 1''',
        [planId],
      );
      if (unfinished.isNotEmpty) {
        final firstUnfinishedDay = unfinished.single['day_index'] as int;
        _database.execute(
          '''UPDATE plan_task
          SET due_date = date(?, '+' || (day_index - ?) || ' days')
          WHERE plan_id = ? AND completed = 0''',
          [_date(today), firstUnfinishedDay, planId],
        );
      }
      final pausedCycles = _database.select(
        '''SELECT c.id, MIN(r.interval_days) AS first_pending_interval
        FROM ebbinghaus_cycle c
        JOIN ebbinghaus_review r ON r.cycle_id = c.id
        WHERE c.source_plan_id = ? AND c.status = 'paused'
          AND r.status = 'pending'
        GROUP BY c.id''',
        [planId],
      );
      for (final cycle in pausedCycles) {
        final cycleId = cycle['id'] as int;
        final firstPendingInterval = cycle['first_pending_interval'] as int;
        final rebasedDate = today.subtract(
          Duration(days: firstPendingInterval),
        );
        _database.execute(
          'UPDATE ebbinghaus_cycle SET base_date = ? WHERE id = ?',
          [_date(rebasedDate), cycleId],
        );
        _database.execute(
          '''UPDATE ebbinghaus_review
          SET due_date = date(?, '+' || interval_days || ' days')
          WHERE cycle_id = ? AND status = 'pending' ''',
          [_date(rebasedDate), cycleId],
        );
      }
      _database.execute(
        "UPDATE memorization_plan SET status = 'active' WHERE id = ?",
        [planId],
      );
      _database.execute(
        '''
        UPDATE ebbinghaus_cycle SET status = 'active'
        WHERE status = 'paused' AND source_plan_id = ?
      ''',
        [planId],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> restartPlan(int planId, {DateTime? startDate}) async {
    final start = DateTime(
      (startDate ?? DateTime.now()).year,
      (startDate ?? DateTime.now()).month,
      (startDate ?? DateTime.now()).day,
    );
    final rows = _database.select(
      '''SELECT COALESCE(s.days, p.days) AS effective_days FROM memorization_plan p
      LEFT JOIN plan_schedule_span s ON s.plan_id = p.id WHERE p.id = ?''',
      [planId],
    );
    if (rows.isEmpty) throw StateError('计划不存在');
    final days = rows.single['effective_days'] as int;
    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'UPDATE memorization_plan SET start_date = ?, end_date = ? WHERE id = ?',
        [_date(start), _date(_storedEndDate(start, days)), planId],
      );
      _saveScheduleSpan(planId, start, days);
      _database.execute(
        '''UPDATE plan_task SET completed = 0,
        due_date = date(?, '+' || day_index || ' days') WHERE plan_id = ?''',
        [_date(start), planId],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<AchievementUnlock>> setTaskCompleted(
    int taskId,
    bool completed,
  ) async {
    final previousRows = _database.select(
      'SELECT completed FROM plan_task WHERE id = ?',
      [taskId],
    );
    final wasCompleted =
        previousRows.isNotEmpty &&
        (previousRows.single['completed'] as int) == 1;
    _database.execute(
      '''UPDATE plan_task SET completed = ?, due_date = CASE WHEN ? = 1 THEN ? ELSE due_date END
      WHERE id = ?''',
      [completed ? 1 : 0, completed ? 1 : 0, _date(DateTime.now()), taskId],
    );
    final unlocked = <AchievementUnlock>[];
    if (completed && !wasCompleted) {
      unlocked.addAll(await _unlockCompletedPresetPlan(taskId));
    }
    unlocked.addAll(await evaluateAndUnlockAchievements(source: 'plan'));
    return unlocked;
  }

  Future<List<AchievementUnlock>> _unlockCompletedPresetPlan(int taskId) async {
    final taskRows = _database.select(
      'SELECT plan_id FROM plan_task WHERE id = ?',
      [taskId],
    );
    if (taskRows.isEmpty) return const [];
    final planId = taskRows.single['plan_id'] as int;
    final plan = (await listPlans())
        .where((item) => item.id == planId)
        .firstOrNull;
    if (plan == null ||
        (plan.sourceKind != PlanSourceKind.preset &&
            plan.sourceKind != PlanSourceKind.cloud) ||
        plan.totalTasks == 0 ||
        plan.completedTasks != plan.totalTasks) {
      return const [];
    }
    final id = 'preset_plan_${plan.externalId ?? plan.id}';
    final existingRows = _database.select(
      'SELECT award_count FROM achievement_unlock WHERE achievement_id = ?',
      [id],
    );
    final nextAwardCount =
        (existingRows.isEmpty ? 0 : existingRows.single['award_count'] as int) +
        1;
    return (await syncExternalAchievementsWithUnlocks(
      [
        AchievementDefinition(
          id: id,
          title: '${plan.title}勋章',
          description: '完成预置计划《${plan.title}》',
          metric: AchievementMetric.sessions,
          target: 1,
          repeatable: true,
        ),
      ],
      {id},
      {id: nextAwardCount.toDouble()},
    )).unlocked;
  }

  Future<void> deleteTask(int taskId) async {
    _database.execute('DELETE FROM plan_task WHERE id = ?', [taskId]);
    await evaluateAndUnlockAchievements(source: 'plan');
  }

  Future<void> moveTaskBlock(int blockId, {required int targetTaskId}) async {
    final source = _database.select(
      'SELECT plan_task_id FROM plan_task_block WHERE id = ?',
      [blockId],
    );
    if (source.isEmpty) throw StateError('背诵条目不存在');
    await moveTaskBlockRange(
      sourceTaskId: source.single['plan_task_id'] as int,
      startBlockId: blockId,
      endBlockId: blockId,
      targetTaskId: targetTaskId,
    );
  }

  /// Moves every persisted block from [startBlockId] through [endBlockId], in
  /// the source entry's reading order.  Moving the final blocks keeps the
  /// historical one-day compression behaviour of [moveTaskBlock].
  Future<void> moveTaskBlockRange({
    required int sourceTaskId,
    required int startBlockId,
    required int endBlockId,
    required int targetTaskId,
  }) async {
    final rows = _database.select(
      '''SELECT b.plan_task_id, t.plan_id, t.day_index, t.completed,
          p.source_kind, p.content_locked, p.start_date,
          COALESCE(s.days, p.days) AS days
        FROM plan_task_block b
        JOIN plan_task t ON t.id = b.plan_task_id
        JOIN memorization_plan p ON p.id = t.plan_id
        LEFT JOIN plan_schedule_span s ON s.plan_id = p.id
        WHERE b.id = ? AND t.id = ?''',
      [startBlockId, sourceTaskId],
    );
    final targets = _database.select(
      '''SELECT t.plan_id, t.completed, p.source_kind, p.content_locked
        FROM plan_task t JOIN memorization_plan p ON p.id = t.plan_id
        WHERE t.id = ?''',
      [targetTaskId],
    );
    if (rows.isEmpty || targets.isEmpty) throw StateError('背诵条目不存在');
    final source = rows.single;
    final target = targets.single;
    if (source['plan_task_id'] == targetTaskId) {
      throw StateError('请选择其他背诵条目');
    }
    if (source['plan_id'] != target['plan_id'] ||
        source['completed'] == 1 ||
        target['completed'] == 1 ||
        source['content_locked'] == 1 ||
        target['content_locked'] == 1 ||
        source['source_kind'] != 'local' ||
        target['source_kind'] != 'local') {
      throw StateError('只有未完成的自定义背诵条目可以调整');
    }
    final sourceDayIndex = source['day_index'] as int;
    final sourceBlocks = _database.select(
      '''SELECT id FROM plan_task_block WHERE plan_task_id = ?
      ORDER BY sort_order, id''',
      [sourceTaskId],
    );
    final sourceBlockIds = [
      for (final block in sourceBlocks) block['id'] as int,
    ];
    final startIndex = sourceBlockIds.indexOf(startBlockId);
    final endIndex = sourceBlockIds.indexOf(endBlockId);
    if (startIndex < 0 || endIndex < 0 || endIndex < startIndex) {
      throw StateError('请选择同一条目内从前到后的经文范围');
    }
    final movingBlockIds = sourceBlockIds.sublist(startIndex, endIndex + 1);
    final sourceBlockCount = sourceBlockIds.length;
    final sourceDayEntryCount =
        _database.select(
              'SELECT COUNT(*) AS count FROM plan_task WHERE plan_id = ? AND day_index = ?',
              [source['plan_id'], sourceDayIndex],
            ).single['count']
            as int;
    final movesAllSourceBlocks = movingBlockIds.length == sourceBlockCount;
    if (movesAllSourceBlocks && sourceDayEntryCount == 1) {
      final completedLater = _database.select(
        '''SELECT 1 FROM plan_task
        WHERE plan_id = ? AND completed = 1 AND day_index > ? LIMIT 1''',
        [source['plan_id'], sourceDayIndex],
      );
      if (completedLater.isNotEmpty) {
        throw StateError('后续已有完成记录，不能缩减这个背诵日');
      }
    }
    _database.execute('BEGIN IMMEDIATE');
    try {
      final placeholders = List.filled(movingBlockIds.length, '?').join(', ');
      _database.execute(
        'UPDATE plan_task_block SET plan_task_id = ? WHERE id IN ($placeholders)',
        [targetTaskId, ...movingBlockIds],
      );
      _reorderTaskBlocks(targetTaskId);
      if (movesAllSourceBlocks) {
        _database.execute('DELETE FROM plan_task WHERE id = ?', [sourceTaskId]);
        if (sourceDayEntryCount == 1) {
          _database.execute(
            '''UPDATE plan_task SET day_index = day_index - 1,
              due_date = date(due_date, '-1 day')
            WHERE plan_id = ? AND day_index > ?''',
            [source['plan_id'], sourceDayIndex],
          );
          final days = (source['days'] as int) - 1;
          final startDate = DateTime.parse(source['start_date'] as String);
          _database.execute(
            'UPDATE memorization_plan SET days = ?, end_date = ? WHERE id = ?',
            [
              _storedDays(days),
              _date(_storedEndDate(startDate, days)),
              source['plan_id'],
            ],
          );
          _saveScheduleSpan(source['plan_id'] as int, startDate, days);
        }
      } else {
        _reorderTaskBlocks(sourceTaskId);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Replaces the source entry's blocks with its remaining verse slices and
  /// appends the selected slices to another unfinished local entry.  The UI
  /// expands scripture ranges before calling this method, so a selection can
  /// start or end inside a persisted block while omitted verses stay omitted.
  Future<void> moveTaskVerseRange({
    required int sourceTaskId,
    required List<NewPlanTaskBlock> sourceBlocks,
    required List<NewPlanTaskBlock> movingBlocks,
    required int targetTaskId,
  }) async {
    if (movingBlocks.isEmpty) throw StateError('请选择至少一节经文');
    final rows = _database.select(
      '''SELECT t.plan_id, t.day_index, t.completed, t.book_id,
          p.source_kind, p.content_locked, p.start_date,
          COALESCE(s.days, p.days) AS days
        FROM plan_task t
        JOIN memorization_plan p ON p.id = t.plan_id
        LEFT JOIN plan_schedule_span s ON s.plan_id = p.id
        WHERE t.id = ?''',
      [sourceTaskId],
    );
    final targets = _database.select(
      '''SELECT t.plan_id, t.completed, t.book_id, p.source_kind,
          p.content_locked
        FROM plan_task t JOIN memorization_plan p ON p.id = t.plan_id
        WHERE t.id = ?''',
      [targetTaskId],
    );
    if (rows.isEmpty || targets.isEmpty) throw StateError('背诵条目不存在');
    final source = rows.single;
    final target = targets.single;
    if (sourceTaskId == targetTaskId) throw StateError('请选择其他背诵条目');
    if (source['plan_id'] != target['plan_id'] ||
        source['completed'] == 1 ||
        target['completed'] == 1 ||
        source['content_locked'] == 1 ||
        target['content_locked'] == 1 ||
        source['source_kind'] != 'local' ||
        target['source_kind'] != 'local') {
      throw StateError('只有未完成的自定义背诵条目可以调整');
    }

    final sourceDayIndex = source['day_index'] as int;
    final sourceDayEntryCount =
        _database.select(
              'SELECT COUNT(*) AS count FROM plan_task WHERE plan_id = ? AND day_index = ?',
              [source['plan_id'], sourceDayIndex],
            ).single['count']
            as int;
    final removesSourceEntry = sourceBlocks.isEmpty;
    if (removesSourceEntry && sourceDayEntryCount == 1) {
      final completedLater = _database.select(
        '''SELECT 1 FROM plan_task
        WHERE plan_id = ? AND completed = 1 AND day_index > ? LIMIT 1''',
        [source['plan_id'], sourceDayIndex],
      );
      if (completedLater.isNotEmpty) {
        throw StateError('后续已有完成记录，不能缩减这个背诵日');
      }
    }

    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute('DELETE FROM plan_task_block WHERE plan_task_id = ?', [
        sourceTaskId,
      ]);
      if (!removesSourceEntry) {
        _insertBlocks(sourceTaskId, sourceBlocks, source['book_id'] as String);
      }
      final targetBlockCount =
          _database.select(
                'SELECT COUNT(*) AS count FROM plan_task_block WHERE plan_task_id = ?',
                [targetTaskId],
              ).single['count']
              as int;
      _insertBlocks(
        targetTaskId,
        movingBlocks,
        target['book_id'] as String,
        startSortOrder: targetBlockCount,
      );
      _reorderTaskBlocks(targetTaskId);
      if (removesSourceEntry) {
        _database.execute('DELETE FROM plan_task WHERE id = ?', [sourceTaskId]);
        if (sourceDayEntryCount == 1) {
          _database.execute(
            '''UPDATE plan_task SET day_index = day_index - 1,
              due_date = date(due_date, '-1 day')
            WHERE plan_id = ? AND day_index > ?''',
            [source['plan_id'], sourceDayIndex],
          );
          final days = (source['days'] as int) - 1;
          final startDate = DateTime.parse(source['start_date'] as String);
          _database.execute(
            'UPDATE memorization_plan SET days = ?, end_date = ? WHERE id = ?',
            [
              _storedDays(days),
              _date(_storedEndDate(startDate, days)),
              source['plan_id'],
            ],
          );
          _saveScheduleSpan(source['plan_id'] as int, startDate, days);
        }
      } else {
        _reorderTaskBlocks(sourceTaskId);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void _reorderTaskBlocks(int taskId) {
    final blocks = _database.select(
      '''SELECT id FROM plan_task_block WHERE plan_task_id = ?
      ORDER BY book_id, start_chapter, start_verse, end_chapter, end_verse, id''',
      [taskId],
    );
    for (var index = 0; index < blocks.length; index++) {
      _database.execute(
        'UPDATE plan_task_block SET sort_order = ? WHERE id = ?',
        [index, blocks[index]['id']],
      );
    }
  }

  /// Moves one unfinished passage onto another scheduled day.  When it was
  /// the last passage on its former day, later days close the gap.
  Future<void> moveTask(int taskId, {required int targetDayIndex}) {
    final rows = _database.select(
      '''SELECT t.plan_id, t.day_index, t.due_date, t.completed, p.source_kind,
          p.content_locked, p.start_date, COALESCE(s.days, p.days) AS days
        FROM plan_task t
        JOIN memorization_plan p ON p.id = t.plan_id
        LEFT JOIN plan_schedule_span s ON s.plan_id = p.id
        WHERE t.id = ?''',
      [taskId],
    );
    if (rows.isEmpty) throw StateError('背诵条目不存在');
    final task = rows.single;
    final planId = task['plan_id'] as int;
    final sourceDayIndex = task['day_index'] as int;
    final sourceDueDate = DateTime.parse(task['due_date'] as String);
    if (task['completed'] == 1) throw StateError('已完成的经文不能调整');
    if (task['content_locked'] == 1 || task['source_kind'] != 'local') {
      throw StateError('只有自定义计划可以调整经文');
    }
    if (targetDayIndex == sourceDayIndex) {
      throw StateError('请选择其他背诵日');
    }
    final targets = _database.select(
      'SELECT 1 FROM plan_task WHERE plan_id = ? AND day_index = ? LIMIT 1',
      [planId, targetDayIndex],
    );
    if (targets.isEmpty) throw StateError('目标背诵日不存在');

    final sourceTaskCount =
        _database.select(
              'SELECT COUNT(*) AS count FROM plan_task WHERE plan_id = ? AND day_index = ?',
              [planId, sourceDayIndex],
            ).single['count']
            as int;
    if (sourceTaskCount == 1) {
      final completedLater = _database.select(
        '''SELECT 1 FROM plan_task
          WHERE plan_id = ? AND completed = 1 AND day_index > ? LIMIT 1''',
        [planId, sourceDayIndex],
      );
      if (completedLater.isNotEmpty) {
        throw StateError('后续已有完成记录，不能缩减这个背诵日');
      }
    }

    _database.execute('BEGIN IMMEDIATE');
    try {
      _database.execute(
        'UPDATE plan_task SET day_index = ?, due_date = ? WHERE id = ?',
        [
          targetDayIndex,
          _date(
            sourceDueDate.add(Duration(days: targetDayIndex - sourceDayIndex)),
          ),
          taskId,
        ],
      );
      if (sourceTaskCount == 1) {
        _database.execute(
          '''UPDATE plan_task SET day_index = day_index - 1,
              due_date = date(due_date, '-1 day')
            WHERE plan_id = ? AND day_index > ?''',
          [planId, sourceDayIndex],
        );
        final days = task['days'] as int;
        final startDate = DateTime.parse(task['start_date'] as String);
        final shortenedDays = days - 1;
        _database.execute(
          'UPDATE memorization_plan SET days = ?, end_date = ? WHERE id = ?',
          [
            _storedDays(shortenedDays),
            _date(_storedEndDate(startDate, shortenedDays)),
            planId,
          ],
        );
        _saveScheduleSpan(planId, startDate, shortenedDays);
      }
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
    return Future<void>.value();
  }

  Future<int> saveRecitationResult(NewRecitationResult result) async {
    _database.execute(
      '''INSERT INTO recitation_result
      (translation_id, book_id, chapter, start_verse, end_verse,
       chapter_verse_count, mode,
       duration_seconds, correct_count, phonetic_correct_count, incorrect_count,
       omitted_count, reordered_count, accuracy, plan_id, started_at, completed_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
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
        result.phoneticCorrectCount,
        result.incorrectCount,
        result.omittedCount,
        result.reorderedCount,
        result.accuracy,
        result.planId,
        result.startedAt?.toUtc().toIso8601String(),
        result.completedAt.toUtc().toIso8601String(),
      ],
    );
    final resultId = _database.lastInsertRowId;
    for (final metric in result.verseMetrics) {
      _database.execute(
        '''INSERT INTO recitation_verse_metric
        (recitation_result_id, plan_id, translation_id, book_id, chapter,
         verse, accuracy, duration_seconds, character_count, started_at, completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
        [
          resultId,
          result.planId,
          result.translationId,
          metric.bookId,
          metric.chapter,
          metric.verse,
          metric.accuracy,
          metric.durationSeconds,
          metric.characterCount,
          result.startedAt?.toUtc().toIso8601String(),
          result.completedAt.toUtc().toIso8601String(),
        ],
      );
    }
    return resultId;
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
    final resultRows = _database.select(
      'SELECT * FROM recitation_result WHERE id = ?',
      [resultId],
    );
    if (resultRows.isEmpty) return;
    final result = resultRows.single;
    final sourcePlanId = result['plan_id'] as int?;
    if (reviewId == null && sourcePlanId == null) return;
    if (reviewId == null) {
      final enabled = _database.select(
        'SELECT ebbinghaus_enabled FROM memorization_plan WHERE id = ?',
        [sourcePlanId],
      );
      if (enabled.isEmpty ||
          (enabled.single['ebbinghaus_enabled'] as int) != 1) {
        return;
      }
    }
    final completedAt = DateTime.parse(result['completed_at'] as String);
    final passed = const EbbinghausScheduler().passes(
      accuracy: (result['accuracy'] as num).toDouble(),
      threshold: settings.passThreshold,
    );

    _database.execute('BEGIN IMMEDIATE');
    try {
      if (reviewId != null) {
        final rows = _database.select(
          '''
          SELECT r.id, r.cycle_id, r.interval_days, c.source_plan_id FROM ebbinghaus_review r
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
            // A later review supersedes all overdue earlier steps for the
            // same passage, including cycles created by older app versions.
            _database.execute(
              '''
              UPDATE ebbinghaus_review
              SET status = 'cancelled'
              WHERE status = 'pending' AND interval_days <= ?
                AND cycle_id IN (
                  SELECT other.id FROM ebbinghaus_cycle other
                  JOIN ebbinghaus_cycle current ON current.id = ?
                  WHERE other.status = 'active'
                    AND other.translation_id = current.translation_id
                    AND other.book_id = current.book_id
                    AND other.start_chapter = current.start_chapter
                    AND other.start_verse = current.start_verse
                    AND other.end_chapter = current.end_chapter
                    AND other.end_verse = current.end_verse
                )
            ''',
              [rows.single['interval_days'] as int, cycleId],
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
            _insertEbbinghausCycle(
              result,
              resultId,
              completedAt,
              sourcePlanId: rows.single['source_plan_id'] as int?,
            );
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
          WHERE source_plan_id = ? AND translation_id = ? AND book_id = ? AND start_chapter = ?
            AND start_verse = ? AND end_chapter = ? AND end_verse = ?
            AND status = 'active'
        ''',
          [
            sourcePlanId,
            result['translation_id'],
            result['book_id'],
            result['chapter'],
            result['start_verse'],
            result['chapter'],
            result['end_verse'],
          ],
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

  void _insertEbbinghausCycle(
    Row result,
    int resultId,
    DateTime baseDate, {
    int? sourcePlanId,
  }) {
    final createdAt = DateTime.now().toUtc().toIso8601String();
    _database.execute(
      '''
      INSERT INTO ebbinghaus_cycle
      (source_result_id, source_plan_id, translation_id, book_id, chapter, start_chapter,
       start_verse, end_chapter, end_verse, base_date, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)
    ''',
      [
        resultId,
        sourcePlanId ?? result['plan_id'],
        result['translation_id'],
        result['book_id'],
        result['chapter'],
        result['chapter'],
        result['start_verse'],
        result['chapter'],
        result['end_verse'],
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

  Future<List<EbbinghausReview>> dueEbbinghausReviews(
    DateTime date, {
    bool includeCompleted = false,
  }) async {
    return _database
        .select(
          '''
          SELECT r.id, r.cycle_id, r.interval_days, r.due_date, r.status,
            c.translation_id, c.book_id, c.chapter, c.start_chapter,
            c.start_verse, c.end_chapter, c.end_verse
          FROM ebbinghaus_review r
          JOIN ebbinghaus_cycle c ON c.id = r.cycle_id
          LEFT JOIN recitation_result result ON result.id = r.result_id
          WHERE (
            (c.status = 'active' AND r.status = 'pending'
              AND r.due_date <= ?)
            OR (? = 1 AND r.status = 'completed'
              AND date(result.completed_at, 'localtime') = ?)
          )
          AND NOT EXISTS (
            SELECT 1 FROM memorization_plan p
            WHERE p.id = c.source_plan_id
              AND (p.status = 'paused' OR p.ebbinghaus_enabled = 0)
          )
          ORDER BY r.interval_days DESC, r.due_date DESC, r.id DESC
        ''',
          [_date(date), includeCompleted ? 1 : 0, _date(date)],
        )
        .map(
          (row) => EbbinghausReview(
            id: row['id'] as int,
            cycleId: row['cycle_id'] as int,
            translationId: row['translation_id'] as String,
            bookId: row['book_id'] as String,
            chapter: row['chapter'] as int,
            startChapter: row['start_chapter'] as int,
            startVerse: row['start_verse'] as int,
            endChapter: row['end_chapter'] as int,
            endVerse: row['end_verse'] as int,
            intervalDays: row['interval_days'] as int,
            dueDate: DateTime.parse(row['due_date'] as String),
            status: row['status'] as String,
            completed: row['status'] == 'completed',
          ),
        )
        .fold(<String, EbbinghausReview>{}, (reviews, review) {
          // Only the furthest overdue step belongs in the review list for a
          // passage. Earlier steps are covered by completing that one.
          final key = [
            review.translationId,
            review.bookId,
            review.startChapter,
            review.startVerse,
            review.endChapter,
            review.endVerse,
          ].join(':');
          reviews.putIfAbsent(key, () => review);
          return reviews;
        })
        .values
        .toList(growable: false);
  }

  Future<List<EbbinghausReview>> listEbbinghausReviewsForPlan(
    int planId,
  ) async => _database
      .select(
        '''SELECT r.id, r.cycle_id, r.interval_days, r.due_date, r.status,
              c.translation_id, c.book_id, c.chapter, c.start_chapter,
              c.start_verse, c.end_chapter, c.end_verse
            FROM ebbinghaus_review r JOIN ebbinghaus_cycle c ON c.id = r.cycle_id
            WHERE c.source_plan_id = ? ORDER BY r.due_date, r.interval_days''',
        [planId],
      )
      .map(
        (row) => EbbinghausReview(
          id: row['id'] as int,
          cycleId: row['cycle_id'] as int,
          translationId: row['translation_id'] as String,
          bookId: row['book_id'] as String,
          chapter: row['chapter'] as int,
          startChapter: row['start_chapter'] as int,
          startVerse: row['start_verse'] as int,
          endChapter: row['end_chapter'] as int,
          endVerse: row['end_verse'] as int,
          intervalDays: row['interval_days'] as int,
          dueDate: DateTime.parse(row['due_date'] as String),
          status: row['status'] as String,
          completed: row['status'] == 'completed',
        ),
      )
      .toList(growable: false);

  Future<List<AchievementUnlock>> evaluateAndUnlockAchievements({
    String source = 'backfill',
  }) async {
    final progress = const AchievementEngine().evaluate(_achievementSnapshot());
    final existing = _database
        .select('SELECT achievement_id, award_count FROM achievement_unlock')
        .map(
          (row) => (
            id: row['achievement_id'] as String,
            count: row['award_count'] as int,
          ),
        )
        .toList(growable: false);
    final existingIds = existing.map((row) => row.id).toSet();
    final now = DateTime.now();
    final unlocked = <AchievementUnlock>[];
    for (final item in progress) {
      if (!item.satisfied || existingIds.contains(item.definition.id)) continue;
      _database.execute(
        '''INSERT OR IGNORE INTO achievement_unlock
        (achievement_id, unlocked_at, source, award_count) VALUES (?, ?, ?, 1)''',
        [item.definition.id, now.toUtc().toIso8601String(), source],
      );
      unlocked.add(
        AchievementUnlock(
          definition: item.definition,
          unlockedAt: now,
          source: source,
          awardCount: 1,
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
    final unlocks = <String, ({DateTime unlockedAt, int awardCount})>{
      for (final row in unlockRows)
        row['achievement_id'] as String: (
          unlockedAt: DateTime.parse(row['unlocked_at'] as String).toLocal(),
          awardCount: row['award_count'] as int,
        ),
    };
    return [
      for (final item in evaluated)
        if (!item.definition.hiddenUntilUnlocked ||
            unlocks.containsKey(item.definition.id))
          AchievementProgress(
            definition: item.definition,
            current: item.current,
            satisfied: item.satisfied,
            unlockedAt: unlocks[item.definition.id]?.unlockedAt,
            awardCount: unlocks[item.definition.id]?.awardCount ?? 0,
          ),
    ];
  }

  Future<List<AchievementProgress>> syncExternalAchievements(
    List<AchievementDefinition> definitions,
    Set<String> satisfiedIds,
    Map<String, double> currentValues,
  ) async => (await syncExternalAchievementsWithUnlocks(
    definitions,
    satisfiedIds,
    currentValues,
  )).progress;

  Future<ExternalAchievementSyncResult> syncExternalAchievementsWithUnlocks(
    List<AchievementDefinition> definitions,
    Set<String> satisfiedIds,
    Map<String, double> currentValues,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final unlockRows = _database.select(
      'SELECT achievement_id, unlocked_at, award_count FROM achievement_unlock',
    );
    final existing = {
      for (final row in unlockRows)
        row['achievement_id'] as String: (
          unlockedAt: DateTime.parse(row['unlocked_at'] as String).toLocal(),
          awardCount: row['award_count'] as int,
        ),
    };
    final definitionsById = {
      for (final definition in definitions) definition.id: definition,
    };
    final unlocked = <AchievementUnlock>[];
    for (final definition in definitions) {
      final id = definition.id;
      final current = currentValues[id] ?? (satisfiedIds.contains(id) ? 1 : 0);
      final previous = existing[id];
      final desiredCount = definition.repeatable
          ? math.max(0, (current / definition.target).floor())
          : (satisfiedIds.contains(id) ? 1 : 0);
      final nextCount = definition.repeatable
          ? math.max(previous?.awardCount ?? 0, desiredCount)
          : (previous?.awardCount ?? desiredCount);
      if (nextCount <= 0 ||
          (previous != null && nextCount == previous.awardCount)) {
        continue;
      }
      if (previous == null) {
        _database.execute(
          '''INSERT OR IGNORE INTO achievement_unlock
          (achievement_id, unlocked_at, source, award_count) VALUES (?, ?, 'coverage', ?)''',
          [id, now, nextCount],
        );
      } else {
        _database.execute(
          'UPDATE achievement_unlock SET award_count = ? WHERE achievement_id = ?',
          [nextCount, id],
        );
      }
      final definitionForUnlock = definitionsById[id];
      if (definitionForUnlock != null) {
        unlocked.add(
          AchievementUnlock(
            definition: definitionForUnlock,
            unlockedAt: DateTime.parse(now).toLocal(),
            source: 'coverage',
            awardCount: nextCount,
          ),
        );
      }
    }
    final unlocks = <String, ({DateTime unlockedAt, int awardCount})>{
      for (final row in _database.select(
        'SELECT achievement_id, unlocked_at, award_count FROM achievement_unlock',
      ))
        row['achievement_id'] as String: (
          unlockedAt: DateTime.parse(row['unlocked_at'] as String).toLocal(),
          awardCount: row['award_count'] as int,
        ),
    };
    final progress = [
      for (final definition in definitions)
        () {
          final stored = unlocks[definition.id];
          final rawCurrent =
              currentValues[definition.id] ??
              (satisfiedIds.contains(definition.id) ? 1 : 0);
          final current = definition.repeatable && stored != null
              ? math.max(rawCurrent, stored.awardCount * definition.target)
              : rawCurrent;
          return AchievementProgress(
            definition: definition,
            current: current,
            satisfied: satisfiedIds.contains(definition.id) || stored != null,
            unlockedAt: stored?.unlockedAt,
            awardCount: stored?.awardCount ?? 0,
          );
        }(),
    ];
    return ExternalAchievementSyncResult(
      progress: progress,
      unlocked: unlocked,
    );
  }

  AchievementSnapshot _achievementSnapshot() {
    final resultRows = _database.select('SELECT * FROM recitation_result');
    final sessionCount = resultRows.length;
    final completedVerseKeys = <String>{};
    var maxAccuracy = 0.0;
    var hasPerfectLongResult = false;
    final activeDates = <DateTime>{};
    final chapterCoverage = <String, Set<int>>{};
    final chapterSizes = <String, int>{};
    for (final row in resultRows) {
      final startVerse = row['start_verse'] as int;
      final endVerse = row['end_verse'] as int;
      for (var verse = startVerse; verse <= endVerse; verse++) {
        completedVerseKeys.add(
          '${row['translation_id']}:${row['book_id']}:${row['chapter']}:$verse',
        );
      }
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
      // A valid full-chapter claim requires a recitation that actually covered
      // the chapter, not repeated attempts at a single verse.
      final size = row['chapter_verse_count'] as int;
      if (startVerse == 1 && endVerse == size && size > 0) {
        chapterSizes[key] = size;
      }
    }
    var streak = 0;
    DateTime? previous;
    final sortedDates = activeDates.toList()..sort();
    for (final date in sortedDates) {
      if (previous != null && date.difference(previous).inDays == 1) {
        streak++;
      } else {
        streak = 1;
      }
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
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final currentStreak =
        previous == null || todayOnly.difference(previous).inDays > 1
        ? 0
        : streak;
    return AchievementSnapshot(
      sessionCount: sessionCount,
      activeDayStreak: currentStreak,
      completedVerses: completedVerseKeys.length,
      maxAccuracy: maxAccuracy,
      hasPerfectLongResult: hasPerfectLongResult,
      completedChapters: completedChapters,
      planCount: planCount,
      completedPlanCount: completedPlanCount,
      recitationDays: activeDates.length,
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

  Future<List<RecitationVerseMetric>> listRecitationVerseMetrics({
    String? translationId,
    String? bookId,
    int? chapter,
  }) async {
    final clauses = <String>[];
    final args = <Object?>[];
    if (translationId != null) {
      clauses.add('translation_id = ?');
      args.add(translationId);
    }
    if (bookId != null) {
      clauses.add('book_id = ?');
      args.add(bookId);
    }
    if (chapter != null) {
      clauses.add('chapter = ?');
      args.add(chapter);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    return _database
        .select('''
      SELECT translation_id, book_id, chapter, verse,
        COUNT(*) AS sessions, AVG(accuracy) AS average_accuracy,
        SUM(duration_seconds) AS total_seconds, SUM(character_count) AS character_count
      FROM recitation_verse_metric $where
      GROUP BY translation_id, book_id, chapter, verse
      ORDER BY translation_id, book_id, chapter, verse
    ''', args)
        .map(
          (row) => RecitationVerseMetric(
            translationId: row['translation_id'] as String,
            bookId: row['book_id'] as String,
            chapter: row['chapter'] as int,
            verse: row['verse'] as int,
            sessions: row['sessions'] as int,
            averageAccuracy: (row['average_accuracy'] as num).toDouble(),
            totalSeconds: row['total_seconds'] as int,
            characterCount: row['character_count'] as int,
          ),
        )
        .toList(growable: false);
  }

  Future<List<RecitationTimelinePoint>> listRecitationTimeline(
    String period,
  ) async {
    final bucket = switch (period) {
      'week' => "strftime('%Y-W%W', completed_at, 'localtime')",
      'month' => "strftime('%Y-%m', completed_at, 'localtime')",
      'quarter' =>
        "strftime('%Y', completed_at, 'localtime') || '-Q' || ((cast(strftime('%m', completed_at, 'localtime') as integer) - 1) / 3 + 1)",
      _ => "strftime('%Y', completed_at, 'localtime')",
    };
    return _database
        .select('''SELECT $bucket AS label, COUNT(*) AS verses,
      SUM(character_count) AS characters, AVG(accuracy) AS accuracy,
      SUM(duration_seconds) AS seconds FROM recitation_verse_metric
      GROUP BY label ORDER BY label''')
        .map(
          (row) => RecitationTimelinePoint(
            row['label'] as String,
            row['verses'] as int,
            row['characters'] as int,
            (row['accuracy'] as num).toDouble(),
            row['seconds'] as int,
          ),
        )
        .toList(growable: false);
  }

  Future<RecitationSummary> getRecitationSummary() async {
    final row = _database.select('''
      WITH RECURSIVE covered(translation_id, book_id, chapter, verse, end_verse) AS (
        SELECT translation_id, book_id, chapter, start_verse, end_verse
        FROM recitation_result
        UNION
        SELECT translation_id, book_id, chapter, verse + 1, end_verse
        FROM covered WHERE verse < end_verse
      )
      SELECT COUNT(*) AS total_sessions,
        (SELECT COUNT(*) FROM (
          SELECT DISTINCT translation_id, book_id, chapter, verse FROM covered
        )) AS total_verses,
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

  Future<LearningStats> getLearningStats() async {
    final calculated = _learningStatsFromRows(
      _database.select('SELECT * FROM recitation_result'),
    );
    final storedMaxDays =
        int.tryParse(await getSetting('max_day_streak', '0')) ?? 0;
    final storedMaxVerses =
        int.tryParse(await getSetting('max_verse_streak', '0')) ?? 0;
    final maxDays = math.max(calculated.maxDayStreak, storedMaxDays);
    final maxVerses = math.max(calculated.maxVerseStreak, storedMaxVerses);
    if (maxDays != storedMaxDays) {
      await setSetting('max_day_streak', '$maxDays');
    }
    if (maxVerses != storedMaxVerses) {
      await setSetting('max_verse_streak', '$maxVerses');
    }
    return LearningStats(
      recitationDays: calculated.recitationDays,
      currentDayStreak: calculated.currentDayStreak,
      maxDayStreak: maxDays,
      currentVerseStreak: calculated.currentVerseStreak,
      maxVerseStreak: maxVerses,
    );
  }

  LearningStats _learningStatsFromRows(List<Row> rows) {
    final versesByDate = <DateTime, int>{};
    for (final row in rows) {
      final completedAt = DateTime.parse(
        row['completed_at'] as String,
      ).toLocal();
      final date = DateTime(
        completedAt.year,
        completedAt.month,
        completedAt.day,
      );
      final verseCount =
          (row['end_verse'] as int) - (row['start_verse'] as int) + 1;
      versesByDate.update(
        date,
        (value) => value + verseCount,
        ifAbsent: () => verseCount,
      );
    }

    final dates = versesByDate.keys.toList()..sort();
    var currentDays = 0;
    var currentVerses = 0;
    var maxDays = 0;
    var maxVerses = 0;
    DateTime? previous;
    for (final date in dates) {
      if (previous != null && date.difference(previous).inDays == 1) {
        currentDays++;
        currentVerses += versesByDate[date]!;
      } else {
        currentDays = 1;
        currentVerses = versesByDate[date]!;
      }
      maxDays = math.max(maxDays, currentDays);
      maxVerses = math.max(maxVerses, currentVerses);
      previous = date;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (previous == null || today.difference(previous).inDays > 1) {
      currentDays = 0;
      currentVerses = 0;
    }
    return LearningStats(
      recitationDays: dates.length,
      currentDayStreak: currentDays,
      maxDayStreak: maxDays,
      currentVerseStreak: currentVerses,
      maxVerseStreak: maxVerses,
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
    days: (row['effective_days'] as int?) ?? row['days'] as int,
    startDate: DateTime.parse(row['start_date'] as String),
    endDate: DateTime.parse(
      (row['effective_end_date'] as String?) ?? row['end_date'] as String,
    ),
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
    ebbinghausEnabled: (row['ebbinghaus_enabled'] as int? ?? 0) == 1,
    paused: (row['status'] as String? ?? 'active') == 'paused',
    recitationSessions: (row['recitation_sessions'] as int?) ?? 0,
    averageAccuracy: (row['average_accuracy'] as num?)?.toDouble() ?? 0,
    totalRecitationSeconds: (row['total_recitation_seconds'] as int?) ?? 0,
  );

  List<PlanTask> _tasksFromRows(List<Row> rows) {
    if (rows.isEmpty) return const [];
    final taskIds = rows.map((row) => row['id'] as int).toList();
    final placeholders = List.filled(taskIds.length, '?').join(', ');
    final blocksByTaskId = <int, List<PlanTaskBlock>>{};
    for (final row in _database.select('''SELECT * FROM plan_task_block
      WHERE plan_task_id IN ($placeholders)
      ORDER BY plan_task_id, sort_order, id''', taskIds)) {
      final taskId = row['plan_task_id'] as int;
      blocksByTaskId
          .putIfAbsent(taskId, () => [])
          .add(
            PlanTaskBlock(
              id: row['id'] as int,
              taskId: taskId,
              sortOrder: row['sort_order'] as int,
              bookId: row['book_id'] as String,
              startChapter: row['start_chapter'] as int,
              startVerse: row['start_verse'] as int,
              endChapter: row['end_chapter'] as int,
              endVerse: row['end_verse'] as int,
            ),
          );
    }
    return rows
        .map(
          (row) =>
              _taskFromRow(row, blocksByTaskId[row['id'] as int] ?? const []),
        )
        .toList(growable: false);
  }

  PlanTask _taskFromRow(Row row, List<PlanTaskBlock> blocks) => PlanTask(
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
    blocks: List.unmodifiable(blocks),
  );

  RecitationResult _resultFromRow(Row row) => RecitationResult(
    id: row['id'] as int,
    translationId: row['translation_id'] as String,
    bookId: row['book_id'] as String,
    chapter: row['chapter'] as int,
    startVerse: row['start_verse'] as int,
    endVerse: row['end_verse'] as int,
    chapterVerseCount: row['chapter_verse_count'] as int,
    planId: row['plan_id'] as int?,
    startedAt: row['started_at'] == null
        ? null
        : DateTime.parse(row['started_at'] as String).toLocal(),
    mode: row['mode'] as String,
    durationSeconds: row['duration_seconds'] as int,
    correctCount: row['correct_count'] as int,
    phoneticCorrectCount: row['phonetic_correct_count'] as int,
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

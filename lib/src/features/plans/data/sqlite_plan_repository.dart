import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import '../../review/domain/ebbinghaus_models.dart';
import '../../review/domain/ebbinghaus_scheduler.dart';
import '../../quiz/domain/quiz_models.dart';
import '../../quiz/domain/quiz_model_settings.dart';
import '../../quiz/domain/quiz_result.dart';
import '../../quiz/domain/quiz_scope.dart';
import '../../statistics/domain/achievement.dart';
import '../../statistics/domain/achievement_engine.dart';
import '../../statistics/domain/recitation_result.dart';
import '../domain/plan_models.dart';

final class SqlitePlanRepository {
  /// Bump this when stricter question validation makes cached unanswered
  /// questions unsuitable. Answered history remains intact for statistics.
  static const quizQuestionQualityVersion = 2;

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
        source TEXT NOT NULL
      )
    ''');
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
        verse_text TEXT NOT NULL,
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
    if (!quizQuestionColumns.contains('verse_text')) {
      _database.execute(
        "ALTER TABLE quiz_question ADD COLUMN verse_text TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!quizQuestionColumns.contains('quality_version')) {
      _database.execute(
        'ALTER TABLE quiz_question ADD COLUMN quality_version INTEGER NOT NULL DEFAULT 1',
      );
    }
    _database.execute('''CREATE INDEX IF NOT EXISTS idx_quiz_question_scope
      ON quiz_question(translation_id, book_id, chapter, verse, answered)''');
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
    _database.execute('''CREATE INDEX IF NOT EXISTS idx_quiz_result_scope
      ON quiz_result(translation_id, book_id, chapter, verse)''');
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
      _database.execute('''UPDATE memorization_plan SET ebbinghaus_enabled =
        COALESCE((SELECT enabled FROM ebbinghaus_settings WHERE id = 1), 0)''');
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
    _database.execute('''CREATE INDEX IF NOT EXISTS idx_plan_task_plan_day
      ON plan_task(plan_id, day_index)''');
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
    _database.execute('PRAGMA user_version = 8');
  }

  final Database _database;

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

  /// Quiz model settings live in app_setting under three keys.
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
    return QuizModelSettings(baseUrl: baseUrl, model: model, apiKey: apiKey);
  }

  Future<void> saveQuizModelSettings(QuizModelSettings settings) async {
    await setSetting('quiz_model_url', settings.baseUrl.trim());
    await setSetting('quiz_model_name', settings.model.trim());
    await setSetting('quiz_model_api_key', settings.apiKey);
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
        end_offset, word, part_of_speech, meaning, reference, verse_text
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
      if (!pending) missing.add(target);
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

  Future<void> saveQuizQuestions(List<ValidatedQuizQuestion> questions) async {
    if (questions.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    _database.execute('BEGIN IMMEDIATE');
    try {
      for (final question in questions) {
        _database.execute(
          '''
          INSERT INTO quiz_question
          (translation_id, book_id, chapter, verse, start_offset, end_offset,
           word, part_of_speech, meaning, reference, verse_text,
           quality_version, created_at)
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
            question.meaning,
            question.reference,
            question.verseText,
            quizQuestionQualityVersion,
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
    verseText: row['verse_text'] as String,
  );

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
    return _database
        .select(
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

  Future<void> setTaskCompleted(int taskId, bool completed) async {
    _database.execute(
      '''UPDATE plan_task SET completed = ?, due_date = CASE WHEN ? = 1 THEN ? ELSE due_date END
      WHERE id = ?''',
      [completed ? 1 : 0, completed ? 1 : 0, _date(DateTime.now()), taskId],
    );
    await evaluateAndUnlockAchievements(source: 'plan');
  }

  Future<void> deleteTask(int taskId) async {
    _database.execute('DELETE FROM plan_task WHERE id = ?', [taskId]);
    await evaluateAndUnlockAchievements(source: 'plan');
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
          SELECT r.id, r.cycle_id, r.interval_days FROM ebbinghaus_review r
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

  void _insertEbbinghausCycle(Row result, int resultId, DateTime baseDate) {
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
        result['plan_id'],
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
    final settings = await getEbbinghausSettings();
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
            SELECT 1 FROM plan_task t
            JOIN memorization_plan p ON p.id = t.plan_id
            WHERE p.status = 'paused'
              AND t.book_id = c.book_id
              AND t.start_chapter = c.start_chapter
              AND t.start_verse = c.start_verse
              AND t.end_chapter = c.end_chapter
              AND t.end_verse = c.end_verse
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
        if (!item.definition.hiddenUntilUnlocked ||
            unlocks.containsKey(item.definition.id))
          AchievementProgress(
            definition: item.definition,
            current: item.current,
            satisfied: item.satisfied,
            unlockedAt: unlocks[item.definition.id],
          ),
    ];
  }

  Future<List<AchievementProgress>> syncExternalAchievements(
    List<AchievementDefinition> definitions,
    Set<String> satisfiedIds,
    Map<String, double> currentValues,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final id in satisfiedIds) {
      _database.execute(
        '''INSERT OR IGNORE INTO achievement_unlock
        (achievement_id, unlocked_at, source) VALUES (?, ?, 'coverage')''',
        [id, now],
      );
    }
    final unlocks = <String, DateTime>{
      for (final row in _database.select(
        'SELECT achievement_id, unlocked_at FROM achievement_unlock',
      ))
        row['achievement_id'] as String: DateTime.parse(
          row['unlocked_at'] as String,
        ).toLocal(),
    };
    return [
      for (final definition in definitions)
        AchievementProgress(
          definition: definition,
          current:
              currentValues[definition.id] ??
              (satisfiedIds.contains(definition.id) ? 1 : 0),
          satisfied: satisfiedIds.contains(definition.id),
          unlockedAt: unlocks[definition.id],
        ),
    ];
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
    final maxDays = max(calculated.maxDayStreak, storedMaxDays);
    final maxVerses = max(calculated.maxVerseStreak, storedMaxVerses);
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
      maxDays = max(maxDays, currentDays);
      maxVerses = max(maxVerses, currentVerses);
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

import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_question_source.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late SqlitePlanRepository repository;
  late Database database;

  setUp(() {
    database = sqlite3.openInMemory();
    repository = SqlitePlanRepository(database);
  });

  tearDown(() => repository.close());

  ValidatedQuizQuestion questionFor({
    int verse = 16,
    int start = 2,
    int end = 4,
    String meaning = '世上的人',
    QuizQuestionSource source = QuizQuestionSource.local,
  }) => ValidatedQuizQuestion(
    reference: '约翰福音 3:$verse',
    translationId: 'cmn-cu89s',
    bookId: 'JHN',
    chapter: 3,
    verse: verse,
    start: start,
    end: end,
    word: '世人',
    partOfSpeech: '名词',
    meaning: meaning,
    verseText: '神爱世人',
    source: source,
  );

  QuizScope scopeFor({int verse = 16}) => QuizScope(
    translationId: 'cmn-cu89s',
    bookId: 'JHN',
    startChapter: 3,
    startVerse: verse,
    endChapter: 3,
    endVerse: verse,
  );

  test(
    'pending question suppresses regeneration and answered verse becomes eligible',
    () async {
      await repository.saveQuizQuestions([questionFor()]);
      expect(
        await repository.listPendingQuizQuestions(scopeFor()),
        hasLength(1),
      );
      expect(await repository.missingQuizVerses(scopeFor()), isEmpty);
      expect(
        await repository.hasPendingQuizQuestion(
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
        ),
        isTrue,
      );

      await repository.completeQuizQuestion(
        questionId: 1,
        correct: true,
        answeredAt: DateTime.now(),
      );
      expect(await repository.listPendingQuizQuestions(scopeFor()), isEmpty);
      expect(await repository.missingQuizVerses(scopeFor()), hasLength(1));
      expect(
        await repository.hasPendingQuizQuestion(
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
        ),
        isFalse,
      );
    },
  );

  test(
    'stores one question for one verse position even if saved repeatedly',
    () async {
      await repository.saveQuizQuestions([questionFor(), questionFor()]);
      await repository.saveQuizQuestions([questionFor()]);

      expect(
        await repository.listPendingQuizQuestions(scopeFor()),
        hasLength(1),
      );
    },
  );

  test(
    'five saved questions keep an answered verse out of generation',
    () async {
      await repository.saveQuizQuestions([
        for (var offset = 0; offset < 5; offset++)
          questionFor(start: offset, end: offset + 1),
      ]);
      for (var id = 1; id <= 5; id++) {
        await repository.completeQuizQuestion(
          questionId: id,
          correct: true,
          answeredAt: DateTime.now(),
        );
      }

      expect(await repository.missingQuizVerses(scopeFor()), isEmpty);
    },
  );

  test(
    'import adds new questions without resetting existing answer history',
    () async {
      await repository.saveQuizQuestions([questionFor()]);
      await repository.completeQuizQuestion(
        questionId: 1,
        correct: true,
        answeredAt: DateTime.now(),
      );

      final result = await repository.importQuizBankQuestions([
        questionFor(),
        questionFor(start: 0, end: 1),
      ]);

      expect(result.imported, 1);
      expect(result.duplicates, 1);
      final summary = await repository.getQuizSummary();
      expect(summary.totalAnswered, 1);
      expect(
        await repository.listPendingQuizQuestions(scopeFor()),
        hasLength(1),
      );
    },
  );

  test('persists cloud source for imported questions', () async {
    final imported = questionFor();
    await repository.importQuizBankQuestions([
      ValidatedQuizQuestion(
        reference: imported.reference,
        translationId: imported.translationId,
        bookId: imported.bookId,
        chapter: imported.chapter,
        verse: imported.verse,
        start: imported.start,
        end: imported.end,
        word: imported.word,
        partOfSpeech: imported.partOfSpeech,
        meaning: imported.meaning,
        verseText: imported.verseText,
        source: QuizQuestionSource.cloud,
      ),
    ]);

    expect(
      (await repository.listPendingQuizQuestions(scopeFor())).single.source,
      QuizQuestionSource.cloud,
    );
    expect(
      (await repository.listQuizBankQuestions()).single.source,
      QuizQuestionSource.cloud,
    );
  });

  test(
    'import refreshes a matching question meaning without resetting history',
    () async {
      await repository.saveQuizQuestions([questionFor()]);
      await repository.completeQuizQuestion(
        questionId: 1,
        correct: true,
        answeredAt: DateTime.now(),
      );

      final result = await repository.importQuizBankQuestions([
        questionFor(meaning: '世上所有的人'),
      ]);

      expect(result.imported, 0);
      expect(result.updated, 1);
      expect(
        (await repository.listQuizBankQuestions()).single.meaning,
        '世上所有的人',
      );
      expect((await repository.getQuizSummary()).totalAnswered, 1);
    },
  );

  test('replacement removes active questions and preserves results', () async {
    await repository.saveQuizQuestions([questionFor()]);
    await repository.completeQuizQuestion(
      questionId: 1,
      correct: true,
      answeredAt: DateTime.utc(2026, 8, 21),
    );
    await repository.stageQuizBankSnapshot(702, [
      questionFor(start: 0, end: 1, meaning: '更新后的具体释义'),
    ]);

    await repository.activateStagedQuizBankSnapshot(702);

    final active = await repository.listQuizBankQuestions();
    expect(active, hasLength(1));
    expect(active.single.start, 0);
    expect(active.single.meaning, '更新后的具体释义');
    expect((await repository.getQuizSummary()).totalAnswered, 1);
    expect(
      database
          .select('SELECT question_id FROM quiz_result')
          .single['question_id'],
      isNull,
    );
  });

  test('staging never changes the active bank', () async {
    await repository.saveQuizQuestions([questionFor()]);

    await repository.stageQuizBankSnapshot(702, [
      questionFor(start: 0, end: 1, meaning: '待切换的新释义'),
    ]);

    final active = await repository.listQuizBankQuestions();
    expect(active, hasLength(1));
    expect(active.single.start, 2);
  });

  test('practice selects one random pending question for one verse', () async {
    await repository.importQuizBankQuestions([
      questionFor(start: 0, end: 1),
      questionFor(start: 1, end: 2),
    ]);

    final questions = await repository.listQuizQuestionsForPractice(scopeFor());

    expect(questions, hasLength(1));
    expect(questions.single.verse, 16);
  });

  test(
    'practice prefers a model question over local fallback questions',
    () async {
      await repository.saveQuizQuestions([
        questionFor(start: 0, end: 1, source: QuizQuestionSource.local),
        questionFor(start: 1, end: 2, source: QuizQuestionSource.model),
      ]);

      final questions = await repository.listQuizQuestionsForPractice(
        scopeFor(),
        preferredSource: QuizQuestionSource.model,
      );

      expect(questions, hasLength(1));
      expect(questions.single.source, QuizQuestionSource.model);
    },
  );

  test(
    'practice can prefer local fallback questions when model is disabled',
    () async {
      await repository.saveQuizQuestions([
        questionFor(start: 0, end: 1, source: QuizQuestionSource.local),
        questionFor(start: 1, end: 2, source: QuizQuestionSource.model),
      ]);

      final questions = await repository.listQuizQuestionsForPractice(
        scopeFor(),
        preferredSource: QuizQuestionSource.local,
      );

      expect(questions, hasLength(1));
      expect(questions.single.source, QuizQuestionSource.local);
    },
  );

  test(
    'random local practice reopens answered questions for a new attempt',
    () async {
      await repository.saveQuizQuestions([
        questionFor(verse: 16),
        questionFor(verse: 17, start: 0, end: 1),
      ]);
      await repository.completeQuizQuestion(
        questionId: 1,
        correct: true,
        answeredAt: DateTime.now(),
      );
      await repository.completeQuizQuestion(
        questionId: 2,
        correct: false,
        answeredAt: DateTime.now(),
      );

      final selected = await repository.listRandomQuizQuestionsForPractice(10);

      expect(selected, hasLength(2));
      expect(
        await repository.listPendingQuizQuestions(scopeFor(verse: 16)),
        hasLength(1),
      );
      expect((await repository.getQuizSummary()).totalAnswered, 2);
    },
  );

  test('random practice can prioritize model questions', () async {
    await repository.saveQuizQuestions([
      questionFor(start: 0, end: 1, source: QuizQuestionSource.local),
      questionFor(start: 1, end: 2, source: QuizQuestionSource.model),
    ]);

    final selected = await repository
        .listRandomQuizQuestionsForPracticeInScopes(
          [scopeFor()],
          1,
          preferredSource: QuizQuestionSource.model,
        );

    expect(selected, hasLength(1));
    expect(selected.single.source, QuizQuestionSource.model);
  });

  test(
    'random local practice stays inside the selected chapter range',
    () async {
      await repository.saveQuizQuestions([
        questionFor(verse: 16),
        const ValidatedQuizQuestion(
          reference: '约翰福音 4:1',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 4,
          verse: 1,
          start: 0,
          end: 1,
          word: '神',
          partOfSpeech: '名词',
          meaning: '神',
          verseText: '神就是爱',
        ),
      ]);

      final selected = await repository
          .listRandomQuizQuestionsForPracticeInScopes(const [
            QuizScope(
              translationId: 'cmn-cu89s',
              bookId: 'JHN',
              startChapter: 3,
              startVerse: 1,
              endChapter: 3,
              endVerse: 36,
            ),
          ], 10);

      expect(selected, hasLength(1));
      expect(selected.single.chapter, 3);
    },
  );

  test(
    'migration merges duplicate question positions before adding uniqueness',
    () {
      final oldDatabase = sqlite3.openInMemory();
      oldDatabase.execute('''CREATE TABLE quiz_question (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      translation_id TEXT NOT NULL, book_id TEXT NOT NULL, chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL, start_offset INTEGER NOT NULL, end_offset INTEGER NOT NULL,
      word TEXT NOT NULL, part_of_speech TEXT NOT NULL, meaning TEXT NOT NULL,
      reference TEXT NOT NULL, verse_text TEXT NOT NULL, quality_version INTEGER NOT NULL,
      answered INTEGER NOT NULL, is_correct INTEGER, answered_at TEXT, created_at TEXT NOT NULL
    )''');
      oldDatabase.execute('''CREATE TABLE quiz_result (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      question_id INTEGER NOT NULL REFERENCES quiz_question(id) ON DELETE CASCADE,
      translation_id TEXT NOT NULL, book_id TEXT NOT NULL, chapter INTEGER NOT NULL,
      verse INTEGER NOT NULL, correct INTEGER NOT NULL, answered_at TEXT NOT NULL
    )''');
      for (var id = 0; id < 2; id++) {
        oldDatabase.execute('''INSERT INTO quiz_question
        (translation_id, book_id, chapter, verse, start_offset, end_offset,
         word, part_of_speech, meaning, reference, verse_text, quality_version,
         answered, created_at)
        VALUES ('cmn-cu89s', 'JHN', 3, 16, 2, 4, '世人', '名词', '世上的人',
          '3:16', '神爱世人', 2, 1, '2026-01-01T00:00:00.000Z')''');
      }
      oldDatabase.execute('''INSERT INTO quiz_result
      (question_id, translation_id, book_id, chapter, verse, correct, answered_at)
      VALUES (2, 'cmn-cu89s', 'JHN', 3, 16, 1, '2026-01-01T00:00:00.000Z')''');

      final migrated = SqlitePlanRepository(oldDatabase);

      expect(oldDatabase.select('SELECT * FROM quiz_question'), hasLength(1));
      expect(
        oldDatabase
            .select('PRAGMA table_info(quiz_question)')
            .map((row) => row['name']),
        isNot(contains('verse_text')),
      );
      expect(
        oldDatabase
            .select('SELECT question_id FROM quiz_result')
            .single['question_id'],
        1,
      );
      migrated.close();
    },
  );

  test('completion updates current and max correct streaks', () async {
    await repository.saveQuizQuestions([
      questionFor(verse: 16),
      questionFor(verse: 17),
    ]);
    final now = DateTime.now();
    await repository.completeQuizQuestion(
      questionId: 1,
      correct: true,
      answeredAt: now,
    );
    await repository.completeQuizQuestion(
      questionId: 2,
      correct: false,
      answeredAt: now.add(const Duration(minutes: 1)),
    );
    final summary = await repository.getQuizSummary();
    expect(summary.totalAnswered, 2);
    expect(summary.totalCorrect, 1);
    expect(summary.currentCorrectStreak, 0);
    expect(summary.maxCorrectStreak, 1);
  });

  test(
    'reuses a completed question without duplicating quiz statistics',
    () async {
      await repository.saveQuizQuestions([questionFor()]);
      final first = await repository.completeQuizQuestion(
        questionId: 1,
        correct: true,
        answeredAt: DateTime.now(),
      );
      final repeated = await repository.completeQuizQuestion(
        questionId: 1,
        correct: false,
        answeredAt: DateTime.now(),
      );
      final summary = await repository.getQuizSummary();
      expect(summary.totalAnswered, 1);
      expect(summary.totalCorrect, 1);
      expect(repeated.totalAnswered, first.totalAnswered);
      expect(repeated.totalCorrect, first.totalCorrect);
      expect(repeated.currentCorrectStreak, first.currentCorrectStreak);
      expect(repeated.maxCorrectStreak, first.maxCorrectStreak);
    },
  );

  test('quiz settings round-trip with blank default key', () async {
    final defaults = await repository.getQuizModelSettings();
    expect(defaults.baseUrl, contains('bigmodel'));
    expect(defaults.model, 'glm-4.7-flash');
    expect(defaults.apiKey, isEmpty);
    expect(defaults.modelAnsweringEnabled, isFalse);

    await repository.saveQuizModelSettings(
      const QuizModelSettings(
        baseUrl: 'https://example.test/v1',
        model: 'custom-model',
        apiKey: 'shhh',
        modelAnsweringEnabled: true,
      ),
    );
    final saved = await repository.getQuizModelSettings();
    expect(saved.baseUrl, 'https://example.test/v1');
    expect(saved.model, 'custom-model');
    expect(saved.apiKey, 'shhh');
    expect(saved.modelAnsweringEnabled, isTrue);

    await repository.clearQuizModelApiKey();
    expect((await repository.getQuizModelSettings()).apiKey, isEmpty);
  });

  test('getRecitationSummary() is unaffected by quiz data', () async {
    await repository.saveQuizQuestions([questionFor()]);
    await repository.completeQuizQuestion(
      questionId: 1,
      correct: true,
      answeredAt: DateTime.now(),
    );
    final summary = await repository.getRecitationSummary();
    expect(summary.totalSessions, 0);
    expect(summary.totalVerses, 0);
    expect(summary.averageAccuracy, 0);
  });

  test('range metrics aggregate only quiz_result', () async {
    await repository.saveQuizQuestions([
      questionFor(verse: 16),
      questionFor(verse: 17, start: 0, end: 1),
    ]);
    await repository.completeQuizQuestion(
      questionId: 1,
      correct: true,
      answeredAt: DateTime.now(),
    );
    await repository.completeQuizQuestion(
      questionId: 2,
      correct: false,
      answeredAt: DateTime.now(),
    );
    final chapterMetric = await repository.getQuizMetric(
      translationId: 'cmn-cu89s',
      bookId: 'JHN',
      chapter: 3,
    );
    expect(chapterMetric.answered, 2);
    expect(chapterMetric.correct, 1);
    final verseMetric = await repository.getQuizMetric(
      translationId: 'cmn-cu89s',
      bookId: 'JHN',
      chapter: 3,
      verse: 16,
    );
    expect(verseMetric.answered, 1);
    expect(verseMetric.correct, 1);
  });
}

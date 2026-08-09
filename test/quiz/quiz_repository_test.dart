import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_model_settings.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late SqlitePlanRepository repository;

  setUp(() {
    repository = SqlitePlanRepository(sqlite3.openInMemory());
  });

  tearDown(() => repository.close());

  ValidatedQuizQuestion questionFor({
    int verse = 16,
    int start = 2,
    int end = 4,
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
    meaning: '世上的人',
    verseText: '神爱世人',
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

    await repository.saveQuizModelSettings(
      const QuizModelSettings(
        baseUrl: 'https://example.test/v1',
        model: 'custom-model',
        apiKey: 'shhh',
      ),
    );
    final saved = await repository.getQuizModelSettings();
    expect(saved.baseUrl, 'https://example.test/v1');
    expect(saved.model, 'custom-model');
    expect(saved.apiKey, 'shhh');

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

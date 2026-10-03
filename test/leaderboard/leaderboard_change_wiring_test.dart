import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_models.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late SqlitePlanRepository repo;
  setUp(() => repo = SqlitePlanRepository(sqlite3.openInMemory()));
  tearDown(() => repo.close());
  test(
    'successful recitation save persists a dirty marker without network',
    () async {
      await repo.saveRecitationResult(
        NewRecitationResult(
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          startVerse: 16,
          endVerse: 16,
          mode: 'continuous',
          durationSeconds: 30,
          correctCount: 4,
          incorrectCount: 0,
          omittedCount: 0,
          reorderedCount: 0,
          accuracy: 1,
          completedAt: DateTime.now(),
        ),
      );
      expect(await repo.getSetting('leaderboard_dirty_since', ''), isNotEmpty);
    },
  );
  test(
    'only a saved profile name marks dirty; unrelated settings do not',
    () async {
      await repo.setSetting('show_recitation_scripture', 'true');
      expect(await repo.getSetting('leaderboard_dirty_since', ''), isEmpty);
      await repo.setSetting('profile_name', '路得');
      expect(await repo.getSetting('leaderboard_dirty_since', ''), isNotEmpty);
    },
  );
  test(
    'repeated quiz answers do not lose deferred dirty state or double count',
    () async {
      await repo.saveQuizQuestions([
        const ValidatedQuizQuestion(
          reference: '约翰福音 3:16',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          chapter: 3,
          verse: 16,
          start: 2,
          end: 4,
          word: '世人',
          partOfSpeech: '名词',
          meaning: '世上的人',
          verseText: '神爱世人',
        ),
      ]);
      await repo.completeQuizQuestion(
        questionId: 1,
        correct: true,
        answeredAt: DateTime.now(),
      );
      expect(await repo.getSetting('leaderboard_dirty_since', ''), isNotEmpty);
      final version = await repo.getSetting('leaderboard_dirty_version', '');
      await repo.completeQuizQuestion(
        questionId: 1,
        correct: true,
        answeredAt: DateTime.now(),
      );
      expect(await repo.getSetting('leaderboard_dirty_version', ''), version);
      expect((await repo.getQuizSummary()).totalAnswered, 1);
    },
  );
  test('failed quiz writes never mark dirty', () async {
    await expectLater(
      repo.completeQuizQuestion(
        questionId: 999,
        correct: true,
        answeredAt: DateTime.now(),
      ),
      throwsStateError,
    );
    expect(await repo.getSetting('leaderboard_dirty_since', ''), isEmpty);
  });
}

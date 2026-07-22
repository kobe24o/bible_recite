import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('persists recitation details and calculates a local summary', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);

    await repository.saveRecitationResult(
      NewRecitationResult(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        startVerse: 16,
        endVerse: 17,
        mode: 'continuous',
        durationSeconds: 42,
        correctCount: 20,
        phoneticCorrectCount: 3,
        incorrectCount: 2,
        omittedCount: 1,
        reorderedCount: 1,
        accuracy: 0.8,
        completedAt: DateTime(2026, 7, 15, 9, 30),
      ),
    );
    await repository.saveRecitationResult(
      NewRecitationResult(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        startVerse: 18,
        endVerse: 18,
        mode: 'verse',
        durationSeconds: 18,
        correctCount: 10,
        incorrectCount: 0,
        omittedCount: 0,
        reorderedCount: 0,
        accuracy: 1,
        completedAt: DateTime(2026, 7, 15, 9, 40),
      ),
    );

    final records = await repository.listRecitationResults();
    expect(records, hasLength(2));
    expect(records.first.mode, 'verse');
    expect(records.last.phoneticCorrectCount, 3);
    final summary = await repository.getRecitationSummary();
    expect(summary.totalSessions, 2);
    expect(summary.totalVerses, 3);
    expect(summary.totalSeconds, 60);
    expect(summary.averageAccuracy, closeTo(0.9, 0.0001));
  });

  test('persists achievement unlocks once and reports progress', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    await repository.saveRecitationResult(
      NewRecitationResult(
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        chapter: 3,
        startVerse: 1,
        endVerse: 1,
        chapterVerseCount: 1,
        mode: 'verse',
        durationSeconds: 10,
        correctCount: 20,
        incorrectCount: 0,
        omittedCount: 0,
        reorderedCount: 0,
        accuracy: 1,
        completedAt: DateTime(2026, 7, 15, 10),
      ),
    );

    final first = await repository.evaluateAndUnlockAchievements(
      source: 'recitation',
    );
    final second = await repository.evaluateAndUnlockAchievements(
      source: 'recitation',
    );
    final ids = first.map((item) => item.definition.id).toSet();

    expect(
      ids,
      containsAll([
        'first_recitation',
        'accuracy_80',
        'accuracy_90',
        'perfect_100',
        'chapter_complete',
      ]),
    );
    expect(second, isEmpty);
    final progress = await repository.listAchievementProgress();
    expect(
      progress
          .singleWhere((item) => item.definition.id == 'perfect_100')
          .unlockedAt,
      isNotNull,
    );
  });
}

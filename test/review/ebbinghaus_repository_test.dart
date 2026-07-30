import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('defaults to disabled with an 80 percent threshold', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);

    final settings = await repository.getEbbinghausSettings();

    expect(settings.enabled, isFalse);
    expect(settings.passThreshold, 0.80);
    expect(settings.enabledAt, isNull);
  });

  test('keeps only the latest overdue review for a passage', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final base = DateTime(2026, 7, 16, 9);
    await repository.updateEbbinghausSettings(
      enabled: true,
      passThreshold: 0.80,
      now: base.subtract(const Duration(minutes: 1)),
    );
    final resultId = await repository.saveRecitationResult(
      _result(accuracy: 0.80, completedAt: base),
    );

    await repository.processEbbinghausResult(resultId: resultId);
    await repository.processEbbinghausResult(resultId: resultId);

    final reviews = await repository.dueEbbinghausReviews(
      base.add(const Duration(days: 30)),
    );
    expect(reviews, hasLength(1));
    expect(reviews.single.intervalDays, 30);
    expect(reviews.first.startVerse, 1);
    expect(reviews.first.endVerse, 36);

    final completedReviewId = await repository.saveRecitationResult(
      _result(accuracy: 1, completedAt: base.add(const Duration(days: 30))),
    );
    await repository.processEbbinghausResult(
      resultId: completedReviewId,
      reviewId: reviews.single.id,
    );
    expect(
      await repository.dueEbbinghausReviews(base.add(const Duration(days: 31))),
      isEmpty,
    );
  });

  test('keeps separate passage reviews in the same chapter', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final base = DateTime(2026, 7, 16, 9);
    await repository.updateEbbinghausSettings(
      enabled: true,
      passThreshold: 0.80,
      now: base.subtract(const Duration(minutes: 1)),
    );
    for (final verse in [16, 17]) {
      final resultId = await repository.saveRecitationResult(
        _result(
          accuracy: 1,
          completedAt: base,
          startVerse: verse,
          endVerse: verse,
          chapterVerseCount: 36,
        ),
      );
      await repository.processEbbinghausResult(resultId: resultId);
    }

    final reviews = await repository.dueEbbinghausReviews(
      base.add(const Duration(days: 1)),
    );
    expect(reviews, hasLength(2));
    expect(reviews.map((review) => review.startVerse), containsAll([16, 17]));
    expect(
      reviews.every((review) => review.endVerse == review.startVerse),
      isTrue,
    );
  });

  test('results before enabling or below threshold do not schedule', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final enabledAt = DateTime(2026, 7, 16, 10);
    await repository.updateEbbinghausSettings(
      enabled: true,
      passThreshold: 0.80,
      now: enabledAt,
    );
    final oldId = await repository.saveRecitationResult(
      _result(
        accuracy: 1,
        completedAt: enabledAt.subtract(const Duration(minutes: 1)),
      ),
    );
    final failedId = await repository.saveRecitationResult(
      _result(accuracy: 0.79, completedAt: enabledAt),
    );

    await repository.processEbbinghausResult(resultId: oldId);
    await repository.processEbbinghausResult(resultId: failedId);

    expect(
      await repository.dueEbbinghausReviews(
        enabledAt.add(const Duration(days: 30)),
      ),
      isEmpty,
    );
  });

  test(
    'a failed review restarts the complete curve from failure day',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final base = DateTime(2026, 7, 16, 9);
      await repository.updateEbbinghausSettings(
        enabled: true,
        passThreshold: 0.80,
        now: base.subtract(const Duration(minutes: 1)),
      );
      final initialId = await repository.saveRecitationResult(
        _result(accuracy: 0.9, completedAt: base),
      );
      await repository.processEbbinghausResult(resultId: initialId);
      final firstReview = (await repository.dueEbbinghausReviews(
        base.add(const Duration(days: 1)),
      )).single;
      final failedAt = base.add(const Duration(days: 1));
      final failedId = await repository.saveRecitationResult(
        _result(accuracy: 0.7, completedAt: failedAt),
      );

      await repository.processEbbinghausResult(
        resultId: failedId,
        reviewId: firstReview.id,
      );

      final restarted = await repository.dueEbbinghausReviews(
        failedAt.add(const Duration(days: 30)),
      );
      expect(restarted, hasLength(1));
      expect(restarted.single.dueDate, DateTime(2026, 8, 16));
    },
  );

  test(
    'disabling hides old cycles and re-enabling only accepts new results',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final base = DateTime(2026, 7, 16, 9);
      await repository.updateEbbinghausSettings(
        enabled: true,
        passThreshold: 0.80,
        now: base,
      );
      final oldId = await repository.saveRecitationResult(
        _result(accuracy: 1, completedAt: base),
      );
      await repository.processEbbinghausResult(resultId: oldId);
      await repository.updateEbbinghausSettings(
        enabled: false,
        passThreshold: 0.80,
        now: base.add(const Duration(hours: 1)),
      );
      await repository.updateEbbinghausSettings(
        enabled: true,
        passThreshold: 0.80,
        now: base.add(const Duration(hours: 2)),
      );

      expect(
        await repository.dueEbbinghausReviews(
          base.add(const Duration(days: 30)),
        ),
        isEmpty,
      );

      final newId = await repository.saveRecitationResult(
        _result(accuracy: 1, completedAt: base.add(const Duration(hours: 3))),
      );
      await repository.processEbbinghausResult(resultId: newId);
      expect(
        await repository.dueEbbinghausReviews(
          base.add(const Duration(days: 31)),
        ),
        hasLength(1),
      );
    },
  );
}

NewRecitationResult _result({
  required double accuracy,
  required DateTime completedAt,
  int startVerse = 1,
  int endVerse = 36,
  int chapterVerseCount = 36,
}) => NewRecitationResult(
  translationId: 'cmn-cu89s',
  bookId: 'JHN',
  chapter: 3,
  startVerse: startVerse,
  endVerse: endVerse,
  chapterVerseCount: chapterVerseCount,
  mode: 'continuous',
  durationSeconds: 60,
  correctCount: (accuracy * 100).round(),
  incorrectCount: 0,
  omittedCount: 0,
  reorderedCount: 0,
  accuracy: accuracy,
  completedAt: completedAt,
);

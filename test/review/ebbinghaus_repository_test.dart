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

  test('a passing result creates six idempotent review dates', () async {
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
    expect(reviews, hasLength(6));
    expect(reviews.map((review) => review.intervalDays), [1, 2, 4, 7, 15, 30]);
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
      expect(restarted, hasLength(6));
      expect(restarted.first.dueDate, DateTime(2026, 7, 18));
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
        hasLength(6),
      );
    },
  );
}

NewRecitationResult _result({
  required double accuracy,
  required DateTime completedAt,
}) => NewRecitationResult(
  translationId: 'cmn-cu89s',
  bookId: 'JHN',
  chapter: 3,
  startVerse: 1,
  endVerse: 36,
  chapterVerseCount: 36,
  mode: 'continuous',
  durationSeconds: 60,
  correctCount: (accuracy * 100).round(),
  incorrectCount: 0,
  omittedCount: 0,
  reorderedCount: 0,
  accuracy: accuracy,
  completedAt: completedAt,
);

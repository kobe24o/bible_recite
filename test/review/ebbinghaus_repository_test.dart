import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'keeps the global threshold but defaults review generation off',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);

      final settings = await repository.getEbbinghausSettings();

      expect(settings.enabled, isFalse);
      expect(settings.passThreshold, .8);
    },
  );

  test('only an enabled source plan creates an exact-range review', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final base = DateTime(2026, 8, 9, 9);
    final planId = await _plan(repository, base, enabled: true);
    final standalone = await repository.saveRecitationResult(
      _result(accuracy: 1, completedAt: base),
    );
    final planned = await repository.saveRecitationResult(
      _result(
        accuracy: 1,
        completedAt: base,
        planId: planId,
        startVerse: 16,
        endVerse: 16,
      ),
    );

    await repository.processEbbinghausResult(resultId: standalone);
    await repository.processEbbinghausResult(resultId: planned);

    final reviews = await repository.dueEbbinghausReviews(
      base.add(const Duration(days: 1)),
    );
    expect(reviews, hasLength(1));
    expect(reviews.single.startVerse, 16);
    expect(reviews.single.endVerse, 16);
  });

  test(
    'pausing one source plan does not hide another plan with the same range',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final base = DateTime(2026, 8, 9, 9);
      final pausedPlan = await _plan(repository, base, enabled: true);
      final activePlan = await _plan(
        repository,
        base,
        enabled: true,
        title: '另一个计划',
      );
      for (final planId in [pausedPlan, activePlan]) {
        final resultId = await repository.saveRecitationResult(
          _result(accuracy: 1, completedAt: base, planId: planId),
        );
        await repository.processEbbinghausResult(resultId: resultId);
      }

      await repository.pausePlan(pausedPlan);

      expect(
        await repository.dueEbbinghausReviews(
          base.add(const Duration(days: 1)),
        ),
        hasLength(1),
      );
    },
  );

  test('a failed review restarts under the original source plan', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final base = DateTime(2026, 8, 9, 9);
    final planId = await _plan(repository, base, enabled: true);
    final source = await repository.saveRecitationResult(
      _result(accuracy: 1, completedAt: base, planId: planId),
    );
    await repository.processEbbinghausResult(resultId: source);
    final first = (await repository.dueEbbinghausReviews(
      base.add(const Duration(days: 1)),
    )).single;
    final failed = await repository.saveRecitationResult(
      _result(accuracy: .7, completedAt: base.add(const Duration(days: 1))),
    );
    await repository.processEbbinghausResult(
      resultId: failed,
      reviewId: first.id,
    );

    final restarted = await repository.listEbbinghausReviewsForPlan(planId);
    expect(restarted.where((review) => review.status == 'pending'), isNotEmpty);
  });
}

Future<int> _plan(
  SqlitePlanRepository repository,
  DateTime date, {
  required bool enabled,
  String title = '复习计划',
}) => repository.createPlan(
  NewMemorizationPlan(
    title: title,
    translationId: 'cmn-cu89s',
    bookId: 'JHN',
    startChapter: 3,
    endChapter: 3,
    startDate: date,
    endDate: date,
    ebbinghausEnabled: enabled,
    tasks: const [
      NewPlanTask(
        dayIndex: 0,
        startChapter: 3,
        startVerse: 1,
        endChapter: 3,
        endVerse: 36,
      ),
    ],
  ),
);

NewRecitationResult _result({
  required double accuracy,
  required DateTime completedAt,
  int startVerse = 1,
  int endVerse = 36,
  int? planId,
}) => NewRecitationResult(
  translationId: 'cmn-cu89s',
  bookId: 'JHN',
  chapter: 3,
  startVerse: startVerse,
  endVerse: endVerse,
  chapterVerseCount: 36,
  mode: 'continuous',
  durationSeconds: 60,
  correctCount: (accuracy * 100).round(),
  incorrectCount: 0,
  omittedCount: 0,
  reorderedCount: 0,
  accuracy: accuracy,
  planId: planId,
  completedAt: completedAt,
);

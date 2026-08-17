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

  test(
    'requires existing plans to opt in again after plan-level migration',
    () async {
      final database = sqlite3.openInMemory();
      database.execute('''
      CREATE TABLE memorization_plan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        translation_id TEXT NOT NULL,
        book_id TEXT NOT NULL,
        start_chapter INTEGER NOT NULL,
        end_chapter INTEGER NOT NULL,
        days INTEGER NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        source_kind TEXT NOT NULL DEFAULT 'local',
        source_url TEXT,
        external_id TEXT,
        revision INTEGER NOT NULL DEFAULT 0,
        content_locked INTEGER NOT NULL DEFAULT 0,
        ebbinghaus_enabled INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL
      )
    ''');
      database.execute('''
      INSERT INTO memorization_plan
      (title, translation_id, book_id, start_chapter, end_chapter, days,
       start_date, end_date, ebbinghaus_enabled, created_at)
      VALUES ('旧计划', 'cmn-cu89s', 'GEN', 1, 1, 1,
              '2026-08-01', '2026-08-01', 1, '2026-08-01T00:00:00Z')
    ''');
      final repository = SqlitePlanRepository(database);
      addTearDown(repository.close);

      expect((await repository.listPlans()).single.ebbinghausEnabled, isFalse);
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

  test('turning off a plan stops its existing Ebbinghaus tasks', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final base = DateTime(2026, 8, 9, 9);
    final planId = await _plan(repository, base, enabled: true);
    final source = await repository.saveRecitationResult(
      _result(accuracy: 1, completedAt: base, planId: planId),
    );
    await repository.processEbbinghausResult(resultId: source);
    expect(
      await repository.dueEbbinghausReviews(base.add(const Duration(days: 1))),
      isNotEmpty,
    );

    await repository.updatePlan(planId, _planDefinition(base, enabled: false));

    expect(
      await repository.dueEbbinghausReviews(base.add(const Duration(days: 1))),
      isEmpty,
    );
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

  test('resuming a plan reschedules its pending reviews from today', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final base = DateTime(2020, 1, 1, 9);
    final planId = await _plan(repository, base, enabled: true);
    final source = await repository.saveRecitationResult(
      _result(accuracy: 1, completedAt: base, planId: planId),
    );
    await repository.processEbbinghausResult(resultId: source);
    await repository.pausePlan(planId);

    await repository.resumePlan(planId);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pending = (await repository.listEbbinghausReviewsForPlan(
      planId,
    )).where((review) => review.status == 'pending').toList(growable: false);
    expect(pending.first.dueDate, today);
    expect(pending[1].dueDate, today.add(const Duration(days: 1)));
    expect(pending[2].dueDate, today.add(const Duration(days: 3)));
  });
}

Future<int> _plan(
  SqlitePlanRepository repository,
  DateTime date, {
  required bool enabled,
  String title = '复习计划',
}) => repository.createPlan(
  _planDefinition(date, enabled: enabled, title: title),
);

NewMemorizationPlan _planDefinition(
  DateTime date, {
  required bool enabled,
  String title = '复习计划',
}) => NewMemorizationPlan(
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

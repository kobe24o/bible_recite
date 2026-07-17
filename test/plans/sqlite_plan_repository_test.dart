import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('stores cloud plan source setting with a default fallback', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);

    expect(await repository.getSetting('cloud_url', 'default'), 'default');
    await repository.setSetting('cloud_url', 'https://example.com/plans.json');
    expect(
      await repository.getSetting('cloud_url', 'default'),
      'https://example.com/plans.json',
    );
  });

  test('persists different books on tasks in one plan', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);

    final id = await repository.createPlan(
      NewMemorizationPlan(
        title: '跨卷计划',
        translationId: 'cmn-cu89s',
        bookId: 'GEN',
        startChapter: 1,
        endChapter: 1,
        startDate: DateTime(2026, 7, 17),
        endDate: DateTime(2026, 7, 18),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            bookId: 'GEN',
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 3,
          ),
          NewPlanTask(
            dayIndex: 1,
            bookId: 'JHN',
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 5,
          ),
        ],
      ),
    );

    expect((await repository.listTasks(id)).map((task) => task.bookId), [
      'GEN',
      'JHN',
    ]);
  });

  test('persists cloud identity and locked content metadata', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);

    await repository.createPlan(
      _plan().copyWith(
        sourceKind: PlanSourceKind.cloud,
        sourceUrl: 'https://example.com/plans.json',
        externalId: 'key-verses-66',
        revision: 3,
        contentLocked: true,
      ),
    );

    final plan = (await repository.listPlans()).single;
    expect(plan.sourceKind, PlanSourceKind.cloud);
    expect(plan.sourceUrl, 'https://example.com/plans.json');
    expect(plan.externalId, 'key-verses-66');
    expect(plan.revision, 3);
    expect(plan.contentLocked, isTrue);
  });

  test('persists a plan and its daily tasks', () async {
    final database = sqlite3.openInMemory();
    final repository = SqlitePlanRepository(database);
    addTearDown(repository.close);

    await repository.createPlan(
      NewMemorizationPlan(
        title: '约翰福音 1–3章',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 1,
        endChapter: 3,
        startDate: DateTime(2026, 7, 14),
        endDate: DateTime(2026, 8, 3),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 5,
          ),
        ],
      ),
    );

    final plans = await repository.listPlans();
    expect(plans, hasLength(1));
    expect(plans.single.days, 21);
    expect(plans.single.completedTasks, 0);
    final tasks = await repository.listTasks(plans.single.id);
    expect(tasks.single.startVerse, 1);
    expect(tasks.single.endVerse, 5);
  });

  test(
    'derives an inclusive end date and can complete then undo a task',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final id = await repository.createPlan(_plan());

      final plan = (await repository.listPlans()).single;
      expect(plan.endDate, DateTime(2026, 7, 16));

      final task = (await repository.listTasks(id)).single;
      await repository.setTaskCompleted(task.id, true);
      expect((await repository.listTasks(id)).single.completed, isTrue);
      await repository.setTaskCompleted(task.id, false);
      expect((await repository.listTasks(id)).single.completed, isFalse);
    },
  );

  test('updates editable fields and keeps completion progress', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final id = await repository.createPlan(_plan());
    final originalTask = (await repository.listTasks(id)).single;
    await repository.setTaskCompleted(originalTask.id, true);

    await repository.updatePlan(
      id,
      NewMemorizationPlan(
        title: '更新后的计划',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 2,
        endChapter: 3,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 2),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 2,
            startVerse: 1,
            endChapter: 2,
            endVerse: 5,
          ),
          NewPlanTask(
            dayIndex: 1,
            startChapter: 2,
            startVerse: 6,
            endChapter: 3,
            endVerse: 5,
          ),
        ],
      ),
    );

    final plan = (await repository.listPlans()).single;
    expect(plan.title, '更新后的计划');
    expect(plan.days, 2);
    expect(plan.completedTasks, 1);
    expect((await repository.listTasks(id)), hasLength(2));
  });

  test('deletes a plan and all of its tasks', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final id = await repository.createPlan(_plan());

    await repository.deletePlan(id);

    expect(await repository.listPlans(), isEmpty);
    expect(await repository.listTasks(id), isEmpty);
  });

  test(
    'today includes overdue work but not completed tasks from older days',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final id = await repository.createPlan(_plan());
      final task = (await repository.listTasks(id)).single;

      expect(
        await repository.dueTasks(
          DateTime(2026, 7, 17),
          includeCompleted: true,
        ),
        hasLength(1),
      );
      await repository.setTaskCompleted(task.id, true);
      expect(
        await repository.dueTasks(
          DateTime(2026, 7, 17),
          includeCompleted: true,
        ),
        isEmpty,
      );
    },
  );
}

NewMemorizationPlan _plan() => NewMemorizationPlan(
  title: '三天计划',
  translationId: 'cmn-cu89s',
  bookId: 'JHN',
  startChapter: 1,
  endChapter: 1,
  startDate: DateTime(2026, 7, 14),
  endDate: DateTime(2026, 7, 16),
  tasks: const [
    NewPlanTask(
      dayIndex: 0,
      startChapter: 1,
      startVerse: 1,
      endChapter: 1,
      endVerse: 5,
    ),
  ],
);

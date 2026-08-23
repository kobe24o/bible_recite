import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/statistics/domain/achievement.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'tracks current and historical best streaks without deduplicating verses',
    () async {
      final database = sqlite3.openInMemory();
      final repository = SqlitePlanRepository(database);
      addTearDown(repository.close);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);

      await repository.saveRecitationResult(
        _result(today.subtract(const Duration(days: 5)), 1, 2),
      );
      await repository.saveRecitationResult(
        _result(today.subtract(const Duration(days: 4)), 1, 1),
      );
      await repository.saveRecitationResult(
        _result(today.subtract(const Duration(days: 1)), 1, 3),
      );
      await repository.saveRecitationResult(_result(today, 1, 2));
      await repository.saveRecitationResult(_result(today, 1, 2));

      final active = await repository.getLearningStats();
      expect(active.recitationDays, 4);
      expect(active.currentDayStreak, 2);
      expect(active.maxDayStreak, 2);
      expect(active.currentVerseStreak, 7);
      expect(active.maxVerseStreak, 7);

      database.execute('DELETE FROM recitation_result');
      final cleared = await repository.getLearningStats();
      expect(cleared.currentDayStreak, 0);
      expect(cleared.currentVerseStreak, 0);
      expect(cleared.maxDayStreak, 2);
      expect(cleared.maxVerseStreak, 7);
    },
  );

  test(
    'keeps real percentage progress for externally calculated badges',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      const definition = AchievementDefinition(
        id: 'book_complete_JHN',
        title: '约翰福音勋章',
        description: '完成约翰福音全部经文',
        metric: AchievementMetric.sessions,
        target: 1,
      );

      final progress = await repository.syncExternalAchievements(
        const [definition],
        const {},
        const {'book_complete_JHN': 0.42},
      );

      expect(progress.single.current, 0.42);
      expect(progress.single.fraction, 0.42);
      expect(progress.single.satisfied, isFalse);
    },
  );

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

  test('migrates every stored task into one exact recitation block', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final id = await repository.createPlan(
      _plan().copyWith(
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 1,
            startVerse: 3,
            endChapter: 2,
            endVerse: 4,
          ),
        ],
      ),
    );

    final task = (await repository.listTasks(id)).single;

    expect(task.blocks, hasLength(1));
    expect(task.blocks.single.rangeLabel, '1:3–2:4');
  });

  test(
    'moves one block into another recitation entry without duplicating it',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final id = await repository.createPlan(
        _plan().copyWith(
          tasks: const [
            NewPlanTask(
              dayIndex: 0,
              startChapter: 1,
              startVerse: 1,
              endChapter: 1,
              endVerse: 1,
              blocks: [
                NewPlanTaskBlock(
                  bookId: 'JHN',
                  startChapter: 1,
                  startVerse: 1,
                  endChapter: 1,
                  endVerse: 1,
                ),
                NewPlanTaskBlock(
                  bookId: 'JHN',
                  startChapter: 1,
                  startVerse: 3,
                  endChapter: 1,
                  endVerse: 3,
                ),
              ],
            ),
            NewPlanTask(
              dayIndex: 1,
              startChapter: 1,
              startVerse: 5,
              endChapter: 1,
              endVerse: 5,
            ),
          ],
        ),
      );
      final before = await repository.listTasks(id);

      await repository.moveTaskBlock(
        before.first.blocks.first.id,
        targetTaskId: before.last.id,
      );

      final entries = await repository.listTasks(id);
      expect(entries, hasLength(2));
      expect(entries.first.blocks.map((block) => block.rangeLabel), ['1:3']);
      expect(entries.last.blocks.map((block) => block.rangeLabel), [
        '1:1',
        '1:5',
      ]);
    },
  );

  test(
    'moves an inclusive block range into another recitation entry',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final id = await repository.createPlan(
        _plan().copyWith(
          tasks: const [
            NewPlanTask(
              dayIndex: 0,
              startChapter: 1,
              startVerse: 1,
              endChapter: 1,
              endVerse: 1,
              blocks: [
                NewPlanTaskBlock(
                  bookId: 'JHN',
                  startChapter: 1,
                  startVerse: 1,
                  endChapter: 1,
                  endVerse: 1,
                ),
                NewPlanTaskBlock(
                  bookId: 'JHN',
                  startChapter: 1,
                  startVerse: 2,
                  endChapter: 1,
                  endVerse: 2,
                ),
                NewPlanTaskBlock(
                  bookId: 'JHN',
                  startChapter: 1,
                  startVerse: 3,
                  endChapter: 1,
                  endVerse: 3,
                ),
              ],
            ),
            NewPlanTask(
              dayIndex: 1,
              startChapter: 1,
              startVerse: 5,
              endChapter: 1,
              endVerse: 5,
            ),
          ],
        ),
      );
      final before = await repository.listTasks(id);

      await repository.moveTaskBlockRange(
        sourceTaskId: before.first.id,
        startBlockId: before.first.blocks[1].id,
        endBlockId: before.first.blocks[2].id,
        targetTaskId: before.last.id,
      );

      final entries = await repository.listTasks(id);
      expect(entries, hasLength(2));
      expect(entries.first.blocks.map((block) => block.rangeLabel), ['1:1']);
      expect(entries.last.blocks.map((block) => block.rangeLabel), [
        '1:2',
        '1:3',
        '1:5',
      ]);
    },
  );

  test(
    'removes an empty source entry and collapses its now-empty day',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final id = await repository.createPlan(
        _plan().copyWith(
          endDate: DateTime(2026, 7, 16),
          tasks: const [
            NewPlanTask(
              dayIndex: 0,
              startChapter: 1,
              startVerse: 1,
              endChapter: 1,
              endVerse: 1,
            ),
            NewPlanTask(
              dayIndex: 1,
              startChapter: 1,
              startVerse: 2,
              endChapter: 1,
              endVerse: 2,
            ),
            NewPlanTask(
              dayIndex: 2,
              startChapter: 1,
              startVerse: 3,
              endChapter: 1,
              endVerse: 3,
            ),
          ],
        ),
      );
      final entries = await repository.listTasks(id);

      await repository.moveTaskBlock(
        entries[1].blocks.single.id,
        targetTaskId: entries.first.id,
      );

      final plan = (await repository.listPlans()).single;
      final remaining = await repository.listTasks(id);
      expect(remaining, hasLength(2));
      expect(remaining.map((task) => task.dayIndex), [0, 1]);
      expect(remaining.first.blocks.map((block) => block.rangeLabel), [
        '1:1',
        '1:2',
      ]);
      expect(plan.days, 2);
      expect(plan.endDate, DateTime(2026, 7, 15));
    },
  );

  test(
    'moving the only unfinished task from a day collapses the schedule',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final id = await repository.createPlan(
        NewMemorizationPlan(
          title: '五天计划',
          translationId: 'cmn-cu89s',
          bookId: 'JHN',
          startChapter: 3,
          endChapter: 3,
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 5),
          tasks: const [
            NewPlanTask(
              dayIndex: 0,
              startChapter: 3,
              startVerse: 16,
              endChapter: 3,
              endVerse: 16,
            ),
            NewPlanTask(
              dayIndex: 1,
              startChapter: 3,
              startVerse: 17,
              endChapter: 3,
              endVerse: 17,
            ),
            NewPlanTask(
              dayIndex: 2,
              startChapter: 3,
              startVerse: 18,
              endChapter: 3,
              endVerse: 18,
            ),
          ],
        ),
      );
      final taskToMove = (await repository.listTasks(id))[1];

      await repository.moveTask(taskToMove.id, targetDayIndex: 0);

      final plan = (await repository.listPlans()).single;
      final tasks = await repository.listTasks(id);
      expect(plan.days, 4);
      expect(plan.endDate, DateTime(2026, 8, 4));
      expect(tasks.map((task) => task.dayIndex), [0, 0, 1]);
      expect(tasks.map((task) => task.dueDate), [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 2),
      ]);
    },
  );

  test('moving one of several passages keeps the schedule duration', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final id = await repository.createPlan(
      NewMemorizationPlan(
        title: '同日多段计划',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 3),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 16,
          ),
          NewPlanTask(
            dayIndex: 1,
            startChapter: 3,
            startVerse: 17,
            endChapter: 3,
            endVerse: 17,
          ),
          NewPlanTask(
            dayIndex: 1,
            startChapter: 3,
            startVerse: 18,
            endChapter: 3,
            endVerse: 18,
          ),
        ],
      ),
    );
    final taskToMove = (await repository.listTasks(id))[1];

    await repository.moveTask(taskToMove.id, targetDayIndex: 0);

    final plan = (await repository.listPlans()).single;
    final tasks = await repository.listTasks(id);
    expect(plan.days, 3);
    expect(plan.endDate, DateTime(2026, 8, 3));
    expect(tasks.map((task) => task.dayIndex), [0, 0, 1]);
  });

  test('does not move completed or locked-plan passages', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final id = await repository.createPlan(
      _plan().copyWith(
        contentLocked: true,
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 1,
          ),
          NewPlanTask(
            dayIndex: 1,
            startChapter: 1,
            startVerse: 2,
            endChapter: 1,
            endVerse: 2,
          ),
        ],
      ),
    );
    final lockedTask = (await repository.listTasks(id)).first;

    expect(
      () => repository.moveTask(lockedTask.id, targetDayIndex: 1),
      throwsStateError,
    );
  });

  test('migrates legacy plans to allow multiple passages on one day', () async {
    final database = sqlite3.openInMemory();
    database.execute('''
      CREATE TABLE plan_task (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL,
        day_index INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        book_id TEXT,
        start_chapter INTEGER NOT NULL,
        start_verse INTEGER NOT NULL,
        end_chapter INTEGER NOT NULL,
        end_verse INTEGER NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        UNIQUE(plan_id, day_index)
      )
    ''');
    final repository = SqlitePlanRepository(database);
    addTearDown(repository.close);

    final id = await repository.createPlan(
      NewMemorizationPlan(
        title: '同日多段',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2026, 7, 25),
        endDate: DateTime(2026, 7, 25),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 16,
          ),
          NewPlanTask(
            dayIndex: 0,
            startChapter: 3,
            startVerse: 17,
            endChapter: 3,
            endVerse: 17,
          ),
        ],
      ),
    );

    expect(await repository.listTasks(id), hasLength(2));
  });

  test('appends selected passages as one future entry across books', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final id = await repository.createPlan(_plan());
    final original = (await repository.listPlans()).single;

    await repository.appendDailyTasks(original, const [
      NewPlanTask(
        dayIndex: 0,
        bookId: 'ROM',
        startChapter: 8,
        startVerse: 28,
        endChapter: 8,
        endVerse: 28,
        blocks: [
          NewPlanTaskBlock(
            bookId: 'ROM',
            startChapter: 8,
            startVerse: 28,
            endChapter: 8,
            endVerse: 28,
          ),
          NewPlanTaskBlock(
            bookId: 'PHP',
            startChapter: 4,
            startVerse: 13,
            endChapter: 4,
            endVerse: 13,
          ),
        ],
      ),
    ]);

    final plan = (await repository.listPlans()).single;
    final tasks = await repository.listTasks(id);
    expect(plan.days, 4);
    expect(plan.endDate, DateTime(2026, 7, 17));
    expect(tasks.map((task) => task.bookId), ['JHN', 'ROM']);
    expect(tasks.map((task) => task.dayIndex), [0, 3]);
    expect(tasks.last.blocks.map((block) => block.bookId), ['ROM', 'PHP']);
    expect(tasks.last.dueDate, DateTime(2026, 7, 17));
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

  test('keeps normal local plans when a long-term plan is added', () async {
    final database = sqlite3.openInMemory();
    final repository = SqlitePlanRepository(database);
    addTearDown(repository.close);
    final normalId = await repository.createPlan(_plan());
    final start = DateTime(2026, 1, 1);
    final end = DateTime(9999, 12, 31);
    final days = end.difference(start).inDays + 1;

    final longId = await repository.createPlan(
      NewMemorizationPlan(
        title: '直到9999年',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 1,
        endChapter: 1,
        startDate: start,
        endDate: end,
        tasks: [
          NewPlanTask(
            dayIndex: days - 1,
            startChapter: 1,
            startVerse: 1,
            endChapter: 1,
            endVerse: 1,
          ),
        ],
      ),
    );

    final plans = await repository.listPlans();
    expect(plans.map((plan) => plan.id), containsAll([normalId, longId]));
    final longPlan = plans.singleWhere((plan) => plan.id == longId);
    expect(longPlan.days, days);
    expect(longPlan.endDate, end);
    expect((await repository.listTasks(longId)).single.dueDate, end);

    final schema =
        database
                .select(
                  "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'memorization_plan'",
                )
                .single['sql']
            as String;
    expect(
      schema,
      contains('days INTEGER NOT NULL CHECK(days BETWEEN 1 AND 365)'),
    );
    expect(
      database.select('SELECT days FROM plan_schedule_span WHERE plan_id = ?', [
        longId,
      ]).single['days'],
      longPlan.days,
    );
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
    'restarts a completed plan from today without changing its duration',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final id = await repository.createPlan(_plan());
      final task = (await repository.listTasks(id)).single;
      await repository.setTaskCompleted(task.id, true);

      await repository.restartPlan(id, startDate: DateTime(2026, 8, 1));

      final plan = (await repository.listPlans()).single;
      final restarted = (await repository.listTasks(id)).single;
      expect(plan.days, 3);
      expect(plan.startDate, DateTime(2026, 8, 1));
      expect(plan.endDate, DateTime(2026, 8, 3));
      expect(restarted.completed, isFalse);
      expect(restarted.dueDate, DateTime(2026, 8, 1));
    },
  );

  test('paused plans no longer provide daily tasks', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final id = await repository.createPlan(_plan());

    await repository.pausePlan(id);

    expect(await repository.dueTasks(DateTime(2026, 7, 15)), isEmpty);
    expect((await repository.listPlans()).single.paused, isTrue);
  });

  test('resumed plans provide daily tasks again', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final id = await repository.createPlan(_plan());
    await repository.pausePlan(id);

    await repository.resumePlan(id);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(await repository.dueTasks(today), hasLength(1));
    expect((await repository.listPlans()).single.paused, isFalse);
  });

  test('resuming a plan reschedules unfinished tasks from today', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final id = await repository.createPlan(
      NewMemorizationPlan(
        title: '已暂停计划',
        translationId: 'cmn-cu89s',
        bookId: 'JHN',
        startChapter: 3,
        endChapter: 3,
        startDate: DateTime(2020, 1, 1),
        endDate: DateTime(2020, 1, 5),
        tasks: const [
          NewPlanTask(
            dayIndex: 0,
            startChapter: 3,
            startVerse: 16,
            endChapter: 3,
            endVerse: 16,
          ),
          NewPlanTask(
            dayIndex: 2,
            startChapter: 3,
            startVerse: 17,
            endChapter: 3,
            endVerse: 17,
          ),
          NewPlanTask(
            dayIndex: 4,
            startChapter: 3,
            startVerse: 18,
            endChapter: 3,
            endVerse: 18,
          ),
        ],
      ),
    );
    final tasks = await repository.listTasks(id);
    await repository.setTaskCompleted(tasks.first.id, true);
    await repository.pausePlan(id);

    await repository.resumePlan(id);

    final resumed = await repository.listTasks(id);
    expect(resumed[0].completed, isTrue);
    expect(resumed[1].dueDate, startOfToday);
    expect(resumed[2].dueDate, startOfToday.add(const Duration(days: 2)));
    expect(await repository.dueTasks(startOfToday), hasLength(1));
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

NewRecitationResult _result(
  DateTime completedAt,
  int startVerse,
  int endVerse,
) => NewRecitationResult(
  translationId: 'cmn-cu89s',
  bookId: 'JHN',
  chapter: 3,
  startVerse: startVerse,
  endVerse: endVerse,
  mode: 'continuous',
  durationSeconds: 30,
  correctCount: 10,
  incorrectCount: 0,
  omittedCount: 0,
  reorderedCount: 0,
  accuracy: 1,
  completedAt: completedAt,
);

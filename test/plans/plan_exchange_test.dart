import 'package:bible_recite/src/features/plans/domain/plan_exchange.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trips a multi-passage daily plan without completion state', () {
    final plan = MemorizationPlan(
      id: 7,
      title: '分享计划',
      translationId: 'cmn-cu89s',
      bookId: 'JHN',
      startChapter: 3,
      endChapter: 3,
      days: 2,
      startDate: DateTime(2026, 7, 25),
      endDate: DateTime(2026, 7, 26),
      completedTasks: 1,
      totalTasks: 2,
      sourceKind: PlanSourceKind.local,
      sourceUrl: null,
      externalId: null,
      revision: 0,
      contentLocked: false,
    );
    final encoded = PlanExchange.encode(plan, [
      PlanTask(
        id: 1,
        planId: 7,
        dayIndex: 0,
        dueDate: DateTime(2026, 7, 25),
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 3,
        endVerse: 16,
        completed: true,
      ),
      PlanTask(
        id: 2,
        planId: 7,
        dayIndex: 0,
        dueDate: DateTime(2026, 7, 25),
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 17,
        endChapter: 3,
        endVerse: 17,
        completed: false,
      ),
    ]);
    final decoded = PlanExchange.decode(encoded);
    expect(decoded.title, '分享计划');
    expect(decoded.tasks, hasLength(2));
    expect(decoded.tasks.every((task) => task.dayIndex == 0), isTrue);
  });
}

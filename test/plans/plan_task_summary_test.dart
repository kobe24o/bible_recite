import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/plans/domain/plan_task_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compacts many blocks into their ordered endpoints', () {
    final summary = compactPlanTaskSummary(
      [
        const PlanTaskBlock(
          id: 1,
          taskId: 1,
          sortOrder: 0,
          bookId: 'GEN',
          startChapter: 1,
          startVerse: 1,
          endChapter: 1,
          endVerse: 1,
        ),
        const PlanTaskBlock(
          id: 2,
          taskId: 1,
          sortOrder: 1,
          bookId: 'EXO',
          startChapter: 1,
          startVerse: 1,
          endChapter: 1,
          endVerse: 1,
        ),
      ],
      bookNameFor: (bookId) => {'GEN': '创世记', 'EXO': '出埃及记'}[bookId]!,
    );

    expect(summary, '创世记 1:1 → 出埃及记 1:1 · 2 个经文段');
  });
}

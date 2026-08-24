import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/plans/domain/plan_task_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compacts many blocks into their ordered endpoints', () {
    final summary = compactPlanTaskSummary([
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
    ], bookNameFor: (bookId) => {'GEN': '创世记', 'EXO': '出埃及记'}[bookId]!);

    expect(summary, '创世记 1:1 → 出埃及记 1:1 · 2 个经文段');
  });

  test('summarizes repeated child blocks as unique book chapters', () {
    final summary = compactPlanTaskChapterSummary([
      const PlanTaskBlock(
        id: 1,
        taskId: 1,
        sortOrder: 0,
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 1,
        endChapter: 3,
        endVerse: 1,
      ),
      const PlanTaskBlock(
        id: 2,
        taskId: 1,
        sortOrder: 1,
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 5,
        endChapter: 3,
        endVerse: 5,
      ),
      const PlanTaskBlock(
        id: 3,
        taskId: 1,
        sortOrder: 2,
        bookId: 'GEN',
        startChapter: 1,
        startVerse: 1,
        endChapter: 1,
        endVerse: 1,
      ),
    ], bookNameFor: (bookId) => {'JHN': '约翰福音', 'GEN': '创世记'}[bookId]!);

    expect(summary, '约翰福音 3章 · 创世记 1章');
  });
}

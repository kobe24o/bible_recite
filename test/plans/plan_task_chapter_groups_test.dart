import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:bible_recite/src/features/plans/domain/plan_task_chapter_groups.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups every task block for one book chapter and preserves gaps', () {
    const blocks = [
      PlanTaskBlock(
        id: 1,
        taskId: 1,
        sortOrder: 0,
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 4,
        endVerse: 2,
      ),
      PlanTaskBlock(
        id: 2,
        taskId: 1,
        sortOrder: 1,
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 5,
        endChapter: 3,
        endVerse: 6,
      ),
      PlanTaskBlock(
        id: 3,
        taskId: 1,
        sortOrder: 2,
        bookId: 'GEN',
        startChapter: 1,
        startVerse: 1,
        endChapter: 1,
        endVerse: 1,
      ),
    ];

    final groups = groupPlanTaskBlocksByChapter(blocks);

    expect(groups, hasLength(3));
    expect((groups[0].bookId, groups[0].chapter), ('JHN', 3));
    expect(groups[0].includesVerse(5), isTrue);
    expect(groups[0].includesVerse(6), isTrue);
    expect(groups[0].includesVerse(16), isTrue);
    expect(groups[0].includesVerse(15), isFalse);
    expect((groups[1].bookId, groups[1].chapter), ('JHN', 4));
    expect(groups[1].includesVerse(1), isTrue);
    expect(groups[1].includesVerse(2), isTrue);
    expect(groups[1].includesVerse(3), isFalse);
    expect((groups[2].bookId, groups[2].chapter), ('GEN', 1));
  });
}

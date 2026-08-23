import 'package:bible_recite/src/features/plans/domain/plan_entry_splitter.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PlanTaskBlock block({
    required String bookId,
    required int startChapter,
    required int startVerse,
    required int endChapter,
    required int endVerse,
  }) => PlanTaskBlock(
    id: 0,
    taskId: 0,
    sortOrder: 0,
    bookId: bookId,
    startChapter: startChapter,
    startVerse: startVerse,
    endChapter: endChapter,
    endVerse: endVerse,
  );

  test(
    'groups every N selected verses without crossing chapter boundaries',
    () {
      final groups = splitPlanEntryBlocks([
        block(
          bookId: 'JHN',
          startChapter: 1,
          startVerse: 1,
          endChapter: 1,
          endVerse: 3,
        ),
        block(
          bookId: 'JHN',
          startChapter: 2,
          startVerse: 1,
          endChapter: 2,
          endVerse: 2,
        ),
      ], const PlanEntrySplitStrategy.everyVerses(2));

      expect(groups, hasLength(3));
      expect(groups.map((group) => group.single.rangeLabel).toList(), [
        '1:1–2',
        '1:3',
        '2:1–2',
      ]);
    },
  );

  test('keeps a selection gap as separate blocks in the default entry', () {
    final groups = splitPlanEntryBlocks([
      block(
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 1,
        endChapter: 3,
        endVerse: 2,
      ),
      block(
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 5,
        endChapter: 3,
        endVerse: 6,
      ),
    ], const PlanEntrySplitStrategy.none());

    expect(groups, hasLength(1));
    expect(groups.single.map((item) => item.rangeLabel), ['3:1–2', '3:5–6']);
  });

  test('groups selected blocks by book chapter or verse', () {
    final blocks = [
      block(
        bookId: 'GEN',
        startChapter: 1,
        startVerse: 1,
        endChapter: 1,
        endVerse: 2,
      ),
      block(
        bookId: 'GEN',
        startChapter: 2,
        startVerse: 1,
        endChapter: 2,
        endVerse: 1,
      ),
      block(
        bookId: 'JHN',
        startChapter: 1,
        startVerse: 1,
        endChapter: 1,
        endVerse: 2,
      ),
    ];

    expect(
      splitPlanEntryBlocks(
        blocks,
        const PlanEntrySplitStrategy.byBook(),
      ).map((group) => group.length),
      [2, 1],
    );
    expect(
      splitPlanEntryBlocks(
        blocks,
        const PlanEntrySplitStrategy.byChapter(),
      ).map((group) => group.length),
      [1, 1, 1],
    );
    expect(
      splitPlanEntryBlocks(
        blocks,
        const PlanEntrySplitStrategy.byVerse(),
      ).map((group) => group.single.rangeLabel),
      ['1:1', '1:2', '2:1', '1:1', '1:2'],
    );
  });
}

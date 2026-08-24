import 'package:bible_recite/src/features/plans/domain/plan_task_verse_slices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const verses = [
    PlanTaskVerse(bookId: 'JHN', chapter: 1, verse: 1),
    PlanTaskVerse(bookId: 'JHN', chapter: 1, verse: 2),
    PlanTaskVerse(bookId: 'JHN', chapter: 1, verse: 3),
    PlanTaskVerse(bookId: 'JHN', chapter: 1, verse: 5),
    PlanTaskVerse(bookId: 'JHN', chapter: 1, verse: 6),
    PlanTaskVerse(bookId: 'JHN', chapter: 1, verse: 7),
    PlanTaskVerse(bookId: 'JHN', chapter: 1, verse: 8),
  ];

  test('moves only existing verses between the selected endpoints', () {
    final slices = splitPlanTaskVersesAtRange(
      verses,
      startIndex: 2,
      endIndex: 5,
    );

    expect(slices.movedVerseCount, 4);
    expect(
      slices.sourceBlocks.map(
        (block) =>
            '${block.startChapter}:${block.startVerse}-${block.endVerse}',
      ),
      ['1:1-2', '1:8-8'],
    );
    expect(
      slices.movingBlocks.map(
        (block) =>
            '${block.startChapter}:${block.startVerse}-${block.endVerse}',
      ),
      ['1:3-3', '1:5-7'],
    );
  });
}

import 'package:bible_recite/src/features/plans/domain/plan_editable_passage_ranges.dart';
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
    taskId: 1,
    sortOrder: 0,
    bookId: bookId,
    startChapter: startChapter,
    startVerse: startVerse,
    endChapter: endChapter,
    endVerse: endVerse,
  );

  test('restores a full continuous book range for plan editing', () async {
    final passages = await collapsePlanTaskBlocksForEditing(
      [
        block(
          bookId: 'GEN',
          startChapter: 1,
          startVerse: 1,
          endChapter: 1,
          endVerse: 3,
        ),
        block(
          bookId: 'GEN',
          startChapter: 2,
          startVerse: 1,
          endChapter: 2,
          endVerse: 2,
        ),
        block(
          bookId: 'EXO',
          startChapter: 1,
          startVerse: 1,
          endChapter: 1,
          endVerse: 2,
        ),
      ],
      chapterVerseCount: (bookId, chapter) async =>
          bookId == 'GEN' && chapter == 1 ? 3 : 2,
    );

    expect(passages, hasLength(2));
    expect(passages.first, const PlanEditablePassage(
      bookId: 'GEN',
      startChapter: 1,
      startVerse: 1,
      endChapter: 2,
      endVerse: 2,
    ));
    expect(passages.last, const PlanEditablePassage(
      bookId: 'EXO',
      startChapter: 1,
      startVerse: 1,
      endChapter: 1,
      endVerse: 2,
    ));
  });

  test('keeps a selection gap as separate editable passages', () async {
    final passages = await collapsePlanTaskBlocksForEditing(
      [
        block(
          bookId: 'GEN',
          startChapter: 1,
          startVerse: 1,
          endChapter: 1,
          endVerse: 1,
        ),
        block(
          bookId: 'GEN',
          startChapter: 1,
          startVerse: 3,
          endChapter: 1,
          endVerse: 3,
        ),
      ],
      chapterVerseCount: (_, _) async => 3,
    );

    expect(passages, hasLength(2));
  });
}

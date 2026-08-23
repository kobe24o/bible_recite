import 'plan_models.dart';

final class PlanEditablePassage {
  const PlanEditablePassage({
    required this.bookId,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
  });

  final String bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;

  @override
  bool operator ==(Object other) =>
      other is PlanEditablePassage &&
      bookId == other.bookId &&
      startChapter == other.startChapter &&
      startVerse == other.startVerse &&
      endChapter == other.endChapter &&
      endVerse == other.endVerse;

  @override
  int get hashCode => Object.hash(
    bookId,
    startChapter,
    startVerse,
    endChapter,
    endVerse,
  );
}

typedef ChapterVerseCount = Future<int> Function(String bookId, int chapter);

Future<List<PlanEditablePassage>> collapsePlanTaskBlocksForEditing(
  Iterable<PlanTaskBlock> blocks, {
  required ChapterVerseCount chapterVerseCount,
}) async {
  final passages = <PlanEditablePassage>[];
  for (final block in blocks) {
    final next = PlanEditablePassage(
      bookId: block.bookId,
      startChapter: block.startChapter,
      startVerse: block.startVerse,
      endChapter: block.endChapter,
      endVerse: block.endVerse,
    );
    if (passages.isEmpty ||
        !await _continues(passages.last, next, chapterVerseCount)) {
      passages.add(next);
      continue;
    }
    final previous = passages.removeLast();
    passages.add(
      PlanEditablePassage(
        bookId: previous.bookId,
        startChapter: previous.startChapter,
        startVerse: previous.startVerse,
        endChapter: next.endChapter,
        endVerse: next.endVerse,
      ),
    );
  }
  return passages;
}

Future<bool> _continues(
  PlanEditablePassage previous,
  PlanEditablePassage next,
  ChapterVerseCount chapterVerseCount,
) async {
  if (previous.bookId != next.bookId) return false;
  if (previous.endChapter == next.startChapter) {
    return previous.endVerse + 1 == next.startVerse;
  }
  if (previous.endChapter + 1 != next.startChapter || next.startVerse != 1) {
    return false;
  }
  return previous.endVerse ==
      await chapterVerseCount(previous.bookId, previous.endChapter);
}

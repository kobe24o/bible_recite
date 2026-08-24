import 'plan_models.dart';

final class PlanTaskVerse {
  const PlanTaskVerse({
    required this.bookId,
    required this.chapter,
    required this.verse,
  });

  final String bookId;
  final int chapter;
  final int verse;
}

final class PlanTaskVerseSlices {
  const PlanTaskVerseSlices({
    required this.sourceBlocks,
    required this.movingBlocks,
    required this.movedVerseCount,
  });

  final List<NewPlanTaskBlock> sourceBlocks;
  final List<NewPlanTaskBlock> movingBlocks;
  final int movedVerseCount;
}

/// Splits the exact verses stored by an entry at two selected verse indices.
/// Missing verses never enter [verses], so they are naturally skipped.
PlanTaskVerseSlices splitPlanTaskVersesAtRange(
  List<PlanTaskVerse> verses, {
  required int startIndex,
  required int endIndex,
}) {
  if (startIndex < 0 || endIndex < startIndex || endIndex >= verses.length) {
    throw RangeError.range(endIndex, 0, verses.length - 1, 'endIndex');
  }
  final moving = verses.sublist(startIndex, endIndex + 1);
  return PlanTaskVerseSlices(
    sourceBlocks: _collapseVerses([
      ...verses.take(startIndex),
      ...verses.skip(endIndex + 1),
    ]),
    movingBlocks: _collapseVerses(moving),
    movedVerseCount: moving.length,
  );
}

List<NewPlanTaskBlock> _collapseVerses(Iterable<PlanTaskVerse> verses) {
  final blocks = <NewPlanTaskBlock>[];
  for (final verse in verses) {
    final previous = blocks.isEmpty ? null : blocks.last;
    final continues =
        previous != null &&
        previous.bookId == verse.bookId &&
        previous.startChapter == verse.chapter &&
        previous.endChapter == verse.chapter &&
        previous.endVerse + 1 == verse.verse;
    if (!continues) {
      blocks.add(
        NewPlanTaskBlock(
          bookId: verse.bookId,
          startChapter: verse.chapter,
          startVerse: verse.verse,
          endChapter: verse.chapter,
          endVerse: verse.verse,
        ),
      );
      continue;
    }
    blocks[blocks.length - 1] = NewPlanTaskBlock(
      bookId: previous.bookId,
      startChapter: previous.startChapter,
      startVerse: previous.startVerse,
      endChapter: verse.chapter,
      endVerse: verse.verse,
    );
  }
  return List.unmodifiable(blocks);
}

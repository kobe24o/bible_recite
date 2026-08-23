import 'plan_models.dart';

enum PlanEntrySplitKind { none, book, chapter, verse, everyVerses }

sealed class PlanEntrySplitStrategy {
  const PlanEntrySplitStrategy();

  PlanEntrySplitKind get kind;
  int? get verseCount => null;

  const factory PlanEntrySplitStrategy.none() = _NoPlanEntrySplit;
  const factory PlanEntrySplitStrategy.byBook() = _ByBookPlanEntrySplit;
  const factory PlanEntrySplitStrategy.byChapter() = _ByChapterPlanEntrySplit;
  const factory PlanEntrySplitStrategy.byVerse() = _ByVersePlanEntrySplit;
  const factory PlanEntrySplitStrategy.everyVerses(int count) =
      _EveryVersesPlanEntrySplit;
}

final class _NoPlanEntrySplit extends PlanEntrySplitStrategy {
  const _NoPlanEntrySplit();

  @override
  PlanEntrySplitKind get kind => PlanEntrySplitKind.none;
}

final class _ByBookPlanEntrySplit extends PlanEntrySplitStrategy {
  const _ByBookPlanEntrySplit();

  @override
  PlanEntrySplitKind get kind => PlanEntrySplitKind.book;
}

final class _ByChapterPlanEntrySplit extends PlanEntrySplitStrategy {
  const _ByChapterPlanEntrySplit();

  @override
  PlanEntrySplitKind get kind => PlanEntrySplitKind.chapter;
}

final class _ByVersePlanEntrySplit extends PlanEntrySplitStrategy {
  const _ByVersePlanEntrySplit();

  @override
  PlanEntrySplitKind get kind => PlanEntrySplitKind.verse;
}

final class _EveryVersesPlanEntrySplit extends PlanEntrySplitStrategy {
  const _EveryVersesPlanEntrySplit(this.count) : assert(count > 0);

  final int count;

  @override
  PlanEntrySplitKind get kind => PlanEntrySplitKind.everyVerses;

  @override
  int get verseCount => count;
}

List<List<PlanTaskBlock>> splitPlanEntryBlocks(
  List<PlanTaskBlock> blocks,
  PlanEntrySplitStrategy strategy,
) {
  final ordered = [...blocks]
    ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  return switch (strategy) {
    _NoPlanEntrySplit() => [ordered],
    _ByBookPlanEntrySplit() => _groupBy(ordered, (block) => block.bookId),
    _ByChapterPlanEntrySplit() => _groupBy(
      ordered,
      (block) => '${block.bookId}:${block.startChapter}',
    ),
    _ByVersePlanEntrySplit() => [
      for (final block in ordered) ..._splitEveryVerses(block, 1),
    ],
    _EveryVersesPlanEntrySplit(:final count) => _groupEveryVerses(
      ordered,
      count,
    ),
  };
}

List<List<PlanTaskBlock>> _groupEveryVerses(
  List<PlanTaskBlock> blocks,
  int count,
) {
  final verses = [
    for (final block in blocks)
      for (final split in _splitEveryVerses(block, 1)) split.single,
  ];
  final groups = <List<PlanTaskBlock>>[];
  for (final verse in verses) {
    final current = groups.isEmpty ? null : groups.last;
    final previous = current == null || current.isEmpty ? null : current.last;
    final continues =
        previous != null &&
        previous.bookId == verse.bookId &&
        previous.startChapter == verse.startChapter &&
        previous.endVerse + 1 == verse.startVerse;
    if (current == null || !continues || current.length == count) {
      groups.add([verse]);
    } else {
      current.add(verse);
    }
  }
  return [
    for (final group in groups)
      group.length == 1
          ? group
          : [
              PlanTaskBlock(
                id: group.first.id,
                taskId: group.first.taskId,
                sortOrder: group.first.sortOrder,
                bookId: group.first.bookId,
                startChapter: group.first.startChapter,
                startVerse: group.first.startVerse,
                endChapter: group.last.endChapter,
                endVerse: group.last.endVerse,
              ),
            ],
  ];
}

List<List<PlanTaskBlock>> _groupBy(
  List<PlanTaskBlock> blocks,
  String Function(PlanTaskBlock block) keyOf,
) {
  final grouped = <String, List<PlanTaskBlock>>{};
  for (final block in blocks) {
    grouped.putIfAbsent(keyOf(block), () => []).add(block);
  }
  return grouped.values.toList(growable: false);
}

Iterable<List<PlanTaskBlock>> _splitEveryVerses(
  PlanTaskBlock block,
  int count,
) {
  if (block.startChapter != block.endChapter) {
    return [
      [block],
    ];
  }
  return [
    for (var start = block.startVerse; start <= block.endVerse; start += count)
      [
        PlanTaskBlock(
          id: block.id,
          taskId: block.taskId,
          sortOrder: block.sortOrder,
          bookId: block.bookId,
          startChapter: block.startChapter,
          startVerse: start,
          endChapter: block.endChapter,
          endVerse: (start + count - 1).clamp(start, block.endVerse),
        ),
      ],
  ];
}

import 'plan_models.dart';

/// One reading or recitation page for a task. The page contains every block
/// that belongs to the same book and chapter, including intentionally skipped
/// verses between its blocks.
final class PlanTaskChapterGroup {
  PlanTaskChapterGroup({
    required this.bookId,
    required this.chapter,
    required List<PlanTaskBlock> blocks,
  }) : blocks = List.unmodifiable(blocks);

  final String bookId;
  final int chapter;
  final List<PlanTaskBlock> blocks;

  bool includesVerse(int verse) {
    for (final block in blocks) {
      final startsInChapter = chapter == block.startChapter;
      final endsInChapter = chapter == block.endChapter;
      final startsAt = startsInChapter ? block.startVerse : 1;
      final endsAt = endsInChapter ? block.endVerse : null;
      if (verse >= startsAt && (endsAt == null || verse <= endsAt)) {
        return true;
      }
    }
    return false;
  }
}

List<PlanTaskChapterGroup> groupPlanTaskBlocksByChapter(
  Iterable<PlanTaskBlock> blocks,
) {
  final groups = <PlanTaskChapterGroup>[];
  for (final block in blocks) {
    for (
      var chapter = block.startChapter;
      chapter <= block.endChapter;
      chapter++
    ) {
      final existing = groups.where(
        (group) => group.bookId == block.bookId && group.chapter == chapter,
      );
      if (existing.isNotEmpty) {
        final group = existing.first;
        groups[groups.indexOf(group)] = PlanTaskChapterGroup(
          bookId: group.bookId,
          chapter: group.chapter,
          blocks: [...group.blocks, block],
        );
      } else {
        groups.add(
          PlanTaskChapterGroup(
            bookId: block.bookId,
            chapter: chapter,
            blocks: [block],
          ),
        );
      }
    }
  }
  return List.unmodifiable(groups);
}

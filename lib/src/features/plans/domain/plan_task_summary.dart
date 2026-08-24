import 'plan_models.dart';
import 'plan_task_chapter_groups.dart';

String compactPlanTaskSummary(
  List<PlanTaskBlock> blocks, {
  required String Function(String bookId) bookNameFor,
}) {
  if (blocks.isEmpty) return '';
  final first = blocks.first;
  if (blocks.length == 1) {
    return '${bookNameFor(first.bookId)} ${first.rangeLabel}';
  }
  final last = blocks.last;
  final end = first.bookId == last.bookId
      ? last.rangeLabel
      : '${bookNameFor(last.bookId)} ${last.rangeLabel}';
  return '${bookNameFor(first.bookId)} ${first.rangeLabel} '
      '→ $end · ${blocks.length} 个经文段';
}

String compactPlanTaskChapterSummary(
  List<PlanTaskBlock> blocks, {
  required String Function(String bookId) bookNameFor,
}) => groupPlanTaskBlocksByChapter(
  blocks,
).map((group) => '${bookNameFor(group.bookId)} ${group.chapter}章').join(' · ');

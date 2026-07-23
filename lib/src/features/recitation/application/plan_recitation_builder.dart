import '../../plans/domain/plan_models.dart';
import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../presentation/recitation_practice_screen.dart';

Future<RecitationRequest?> buildPlanRecitationRequest({
  required ScriptureRepository scripture,
  required MemorizationPlan plan,
  required List<PlanTask> tasks,
  required PlanTask selected,
}) async {
  final pending =
      tasks
          .where(
            (task) => task.dayIndex >= selected.dayIndex && !task.completed,
          )
          .toList()
        ..sort((left, right) => left.dayIndex.compareTo(right.dayIndex));
  if (pending.isEmpty) return null;

  RecitationRequest? next;
  for (final task in pending.reversed) {
    final passage = await scripture.getPassage(
      plan.translationId,
      PassageRange(
        start: (
          canonId: CanonId.protestant66,
          osisBookId: task.bookId,
          chapter: task.startChapter,
          verse: task.startVerse,
        ),
        end: (
          canonId: CanonId.protestant66,
          osisBookId: task.bookId,
          chapter: task.endChapter,
          verse: task.endVerse,
        ),
      ),
    );
    next = RecitationRequest(
      translationId: plan.translationId,
      bookId: task.bookId,
      chapter: task.startChapter,
      mode: RecitationMode.continuous,
      units: passage.units,
      next: next,
    );
  }
  return next;
}

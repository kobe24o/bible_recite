import '../../plans/domain/plan_models.dart';
import '../../quiz/domain/quiz_scope.dart';
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
            (task) =>
                task.dayIndex >= selected.dayIndex &&
                (!task.completed || task.id == selected.id),
          )
          .toList()
        ..sort((left, right) => left.dayIndex.compareTo(right.dayIndex));
  if (pending.isEmpty) return null;
  final quizScope = _quizScopeForPlan(plan, tasks);

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
      planTaskId: task.id,
      planId: plan.id,
      next: next,
      quizScope: task.id == selected.id ? quizScope : null,
    );
  }
  return next;
}

QuizScope? _quizScopeForPlan(MemorizationPlan plan, List<PlanTask> tasks) {
  final inPlanBook = tasks
      .where((task) => task.bookId == plan.bookId)
      .toList(growable: false);
  if (inPlanBook.isEmpty) return null;
  final ordered = [...inPlanBook]
    ..sort((left, right) {
      final chapter = left.startChapter.compareTo(right.startChapter);
      if (chapter != 0) return chapter;
      return left.startVerse.compareTo(right.startVerse);
    });
  final first = ordered.first;
  final last = ordered.reduce((latest, task) {
    final laterChapter = task.endChapter.compareTo(latest.endChapter);
    if (laterChapter > 0 ||
        (laterChapter == 0 && task.endVerse > latest.endVerse)) {
      return task;
    }
    return latest;
  });
  return QuizScope(
    translationId: plan.translationId,
    bookId: plan.bookId,
    startChapter: first.startChapter,
    startVerse: first.startVerse,
    endChapter: last.endChapter,
    endVerse: last.endVerse,
  );
}

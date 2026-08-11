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
  bool todayQuizEntry = false,
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
  // A Today task must only prepare questions for the passage the user opened
  // today. Passing every range in a long plan here turns one task into a
  // several-hundred-question run once the shared bank has accumulated data.
  // Non-Today plan flows retain their plan-wide, disjoint-range behavior.
  final quizScopes = todayQuizEntry
      ? [_quizScopeForTask(plan, selected)]
      : _quizScopesForPlan(plan, tasks);

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
      // Every screen in the chain needs the exact task scopes so the final
      // task can enter the quiz. Discrete plan ranges must not be compressed
      // into one continuous interval, otherwise gaps become quiz questions.
      quizScope: quizScopes.isEmpty ? null : quizScopes.first,
      quizScopes: quizScopes,
      todayQuizEntry: todayQuizEntry,
    );
  }
  return next;
}

List<QuizScope> _quizScopesForPlan(
  MemorizationPlan plan,
  List<PlanTask> tasks,
) => {
  for (final task in tasks)
    QuizScope(
      translationId: plan.translationId,
      bookId: task.bookId,
      startChapter: task.startChapter,
      startVerse: task.startVerse,
      endChapter: task.endChapter,
      endVerse: task.endVerse,
    ),
}.toList(growable: false);

QuizScope _quizScopeForTask(MemorizationPlan plan, PlanTask task) => QuizScope(
  translationId: plan.translationId,
  bookId: task.bookId,
  startChapter: task.startChapter,
  startVerse: task.startVerse,
  endChapter: task.endChapter,
  endVerse: task.endVerse,
);

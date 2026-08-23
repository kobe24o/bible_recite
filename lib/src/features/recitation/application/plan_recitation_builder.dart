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
  final blocks = selected.effectiveBlocks;
  if (blocks.isEmpty) return null;
  // A recitation entry owns its own ordered blocks.  Do not make an entry
  // launch later scheduled entries: that turns a user's single Today row back
  // into several unrelated tasks.
  final quizScopes = [
    for (final block in blocks) _quizScopeForBlock(plan, block),
  ];

  RecitationRequest? next;
  for (final block in blocks.reversed) {
    final passage = await scripture.getPassage(
      plan.translationId,
      PassageRange(
        start: (
          canonId: CanonId.protestant66,
          osisBookId: block.bookId,
          chapter: block.startChapter,
          verse: block.startVerse,
        ),
        end: (
          canonId: CanonId.protestant66,
          osisBookId: block.bookId,
          chapter: block.endChapter,
          verse: block.endVerse,
        ),
      ),
    );
    next = RecitationRequest(
      translationId: plan.translationId,
      bookId: block.bookId,
      chapter: block.startChapter,
      mode: RecitationMode.continuous,
      units: passage.units,
      planTaskId: next == null ? selected.id : null,
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

QuizScope _quizScopeForBlock(MemorizationPlan plan, PlanTaskBlock block) =>
    QuizScope(
      translationId: plan.translationId,
      bookId: block.bookId,
      startChapter: block.startChapter,
      startVerse: block.startVerse,
      endChapter: block.endChapter,
      endVerse: block.endVerse,
    );

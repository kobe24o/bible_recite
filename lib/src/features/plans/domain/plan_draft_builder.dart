import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../presentation/plan_editor_dialog.dart';
import 'plan_generator.dart';
import 'plan_models.dart';

Future<NewMemorizationPlan> buildPlanFromDraft(
  ScriptureRepository scripture,
  PlanEditorDraft draft,
) async {
  final units = <VerseUnit>[];
  for (
    var chapter = draft.startChapter;
    chapter <= draft.endChapter;
    chapter++
  ) {
    units.addAll(
      await scripture.getChapter(draft.translationId, draft.bookId, chapter),
    );
  }
  if (units.isEmpty) throw StateError('所选章节没有可用经文');
  final chunks = const PlanGenerator().generate(units: units, days: draft.days);
  final lastUnit = units.last;
  final tasks = chunks
      .map((chunk) {
        final selected = chunk.units.isEmpty ? [lastUnit] : chunk.units;
        return NewPlanTask(
          dayIndex: chunk.dayIndex,
          startChapter: selected.first.start.chapter,
          startVerse: selected.first.start.verse,
          endChapter: selected.last.end.chapter,
          endVerse: selected.last.end.verse,
        );
      })
      .toList(growable: false);
  return NewMemorizationPlan(
    title: draft.title,
    translationId: draft.translationId,
    bookId: draft.bookId,
    startChapter: draft.startChapter,
    endChapter: draft.endChapter,
    startDate: draft.startDate,
    endDate: draft.endDate,
    tasks: tasks,
  );
}

import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../presentation/plan_editor_dialog.dart';
import 'plan_generator.dart';
import 'plan_models.dart';

Future<NewMemorizationPlan> buildPlanFromDraft(
  ScriptureRepository scripture,
  PlanEditorDraft draft, {
  List<PlanTask> completedTasks = const [],
}) async {
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
  final completedDays = completedTasks.map((task) => task.dayIndex).toSet();
  final availableDays = [
    for (var day = 0; day < draft.days; day++)
      if (!completedDays.contains(day)) day,
  ];
  final pendingUnits = units
      .where((unit) => !completedTasks.any((task) => _contains(task, unit)))
      .toList(growable: false);
  final chunks = availableDays.isEmpty || pendingUnits.isEmpty
      ? const <GeneratedPlanTask>[]
      : const PlanGenerator().generate(
          units: pendingUnits,
          days: availableDays.length,
        );
  final tasks = <NewPlanTask>[
    for (final task in completedTasks)
      NewPlanTask(
        dayIndex: task.dayIndex,
        bookId: task.bookId,
        startChapter: task.startChapter,
        startVerse: task.startVerse,
        endChapter: task.endChapter,
        endVerse: task.endVerse,
      ),
    for (final chunk in chunks)
      if (chunk.units.isNotEmpty)
        (() {
          final selected = chunk.units;
          return NewPlanTask(
            dayIndex: availableDays[chunk.dayIndex],
            bookId: selected.first.start.osisBookId,
            startChapter: selected.first.start.chapter,
            startVerse: selected.first.start.verse,
            endChapter: selected.last.end.chapter,
            endVerse: selected.last.end.verse,
          );
        })(),
  ]..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
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

bool _contains(PlanTask task, VerseUnit unit) {
  if (task.bookId != unit.start.osisBookId) return false;
  final start = (task.startChapter, task.startVerse);
  final end = (task.endChapter, task.endVerse);
  final unitStart = (unit.start.chapter, unit.start.verse);
  final unitEnd = (unit.end.chapter, unit.end.verse);
  return _compare(start, unitStart) <= 0 && _compare(unitEnd, end) <= 0;
}

int _compare((int, int) left, (int, int) right) => left.$1 != right.$1
    ? left.$1.compareTo(right.$1)
    : left.$2.compareTo(right.$2);

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
  final passageUnits = <List<VerseUnit>>[];
  if (draft.passages.isEmpty) {
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
    passageUnits.add(units);
  } else {
    for (final passage in draft.passages) {
      passageUnits.add(
        (await scripture.getPassage(
          draft.translationId,
          PassageRange(
            start: (
              canonId: CanonId.protestant66,
              osisBookId: passage.bookId,
              chapter: passage.startChapter,
              verse: passage.startVerse,
            ),
            end: (
              canonId: CanonId.protestant66,
              osisBookId: passage.bookId,
              chapter: passage.endChapter,
              verse: passage.endVerse,
            ),
          ),
        )).units,
      );
    }
  }
  if (passageUnits.every((units) => units.isEmpty)) {
    throw StateError('所选章节没有可用经文');
  }
  final completedDays = completedTasks.map((task) => task.dayIndex).toSet();
  final availableDays = [
    for (var day = 0; day < draft.days; day++)
      if (!completedDays.contains(day)) day,
  ];
  final pendingPassages = passageUnits
      .map(
        (units) => units
            .where(
              (unit) => !completedTasks.any((task) => _contains(task, unit)),
            )
            .toList(growable: false),
      )
      .where((units) => units.isNotEmpty)
      .toList(growable: false);
  if (pendingPassages.length > availableDays.length) {
    throw StateError('剩余天数不足，无法为每段经文安排独立的背诵任务');
  }
  final dayCounts = _allocateDays(pendingPassages, availableDays.length);
  var dayCursor = 0;
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
  ];
  for (
    var passageIndex = 0;
    passageIndex < pendingPassages.length;
    passageIndex++
  ) {
    final chunks = const PlanGenerator().generate(
      units: pendingPassages[passageIndex],
      days: dayCounts[passageIndex],
    );
    for (final chunk in chunks) {
      if (chunk.units.isEmpty) continue;
      final selected = chunk.units;
      tasks.add(
        NewPlanTask(
          dayIndex: availableDays[dayCursor + chunk.dayIndex],
          bookId: selected.first.start.osisBookId,
          startChapter: selected.first.start.chapter,
          startVerse: selected.first.start.verse,
          endChapter: selected.last.end.chapter,
          endVerse: selected.last.end.verse,
        ),
      );
    }
    dayCursor += dayCounts[passageIndex];
  }
  tasks.sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
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

List<int> _allocateDays(List<List<VerseUnit>> passages, int totalDays) {
  if (passages.isEmpty) return const [];
  final weights = [
    for (final passage in passages)
      passage.fold<int>(
        0,
        (total, unit) =>
            total + unit.text.replaceAll(RegExp(r'\s+'), '').runes.length,
      ),
  ];
  final days = List<int>.filled(passages.length, 1);
  var remaining = totalDays - passages.length;
  while (remaining > 0) {
    var selected = 0;
    for (var index = 1; index < passages.length; index++) {
      final left = days[index] / (weights[index] == 0 ? 1 : weights[index]);
      final right =
          days[selected] / (weights[selected] == 0 ? 1 : weights[selected]);
      if (left < right) selected = index;
    }
    days[selected]++;
    remaining--;
  }
  return days;
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

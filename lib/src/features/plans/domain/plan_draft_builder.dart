import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../presentation/plan_editor_dialog.dart';
import 'plan_generator.dart';
import 'plan_models.dart';

PlanEditorDraft normalizeDraftForPendingWork(
  PlanEditorDraft draft,
  List<PlanTask> completedTasks, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final anchor = today.isAfter(draft.startDate) ? today : draft.startDate;
  final completedEnd = completedTasks.isEmpty
      ? draft.startDate
      : draft.startDate.add(
          Duration(
            days: completedTasks
                .map((task) => task.dayIndex)
                .reduce((a, b) => a > b ? a : b),
          ),
        );
  final end = [
    draft.endDate,
    completedEnd,
    anchor,
  ].reduce((a, b) => a.isAfter(b) ? a : b);
  if (end == draft.endDate) return draft;
  return PlanEditorDraft(
    title: draft.title,
    translationId: draft.translationId,
    bookId: draft.bookId,
    startChapter: draft.startChapter,
    endChapter: draft.endChapter,
    startDate: draft.startDate,
    endDate: end,
    passages: draft.passages,
  );
}

Future<NewMemorizationPlan> buildPlanFromDraft(
  ScriptureRepository scripture,
  PlanEditorDraft draft, {
  List<PlanTask> completedTasks = const [],
  DateTime? now,
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
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final availableDays = [
    for (var day = 0; day < draft.days; day++)
      if (!completedDays.contains(day) &&
          !draft.startDate.add(Duration(days: day)).isBefore(today))
        day,
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
  if (availableDays.isEmpty && pendingPassages.isNotEmpty) {
    throw StateError('请将结束日期调整到今天或之后');
  }
  // When a plan is shortened there can be more selected passages than days.
  // Keep every verse atomic, then place multiple passage tasks on a day rather
  // than silently extending the date range again.
  final dayCounts = availableDays.length >= pendingPassages.length
      ? _allocateDays(pendingPassages, availableDays.length)
      : List<int>.filled(pendingPassages.length, 1);
  final combinePassagesOnDay = pendingPassages.length > availableDays.length;
  final pendingTasks = <NewPlanTask>[];
  final pendingWeights = <int>[];
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
  var dayCursor = 0;
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
      final task = NewPlanTask(
        dayIndex: chunk.dayIndex,
        bookId: selected.first.start.osisBookId,
        startChapter: selected.first.start.chapter,
        startVerse: selected.first.start.verse,
        endChapter: selected.last.end.chapter,
        endVerse: selected.last.end.verse,
      );
      if (combinePassagesOnDay) {
        pendingTasks.add(task);
        pendingWeights.add(_weight(selected));
      } else {
        tasks.add(
          NewPlanTask(
            dayIndex: availableDays[dayCursor + chunk.dayIndex],
            bookId: task.bookId,
            startChapter: task.startChapter,
            startVerse: task.startVerse,
            endChapter: task.endChapter,
            endVerse: task.endVerse,
          ),
        );
      }
    }
    dayCursor += dayCounts[passageIndex];
  }
  if (combinePassagesOnDay) {
    final assignedDays = _balancedDayIndexes(
      pendingWeights,
      availableDays.length,
    );
    for (var index = 0; index < pendingTasks.length; index++) {
      final task = pendingTasks[index];
      tasks.add(
        NewPlanTask(
          dayIndex: availableDays[assignedDays[index]],
          bookId: task.bookId,
          startChapter: task.startChapter,
          startVerse: task.startVerse,
          endChapter: task.endChapter,
          endVerse: task.endVerse,
        ),
      );
    }
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

List<int> _balancedDayIndexes(List<int> weights, int days) {
  if (weights.isEmpty) return const [];
  final total = weights.fold<int>(0, (sum, weight) => sum + weight);
  final target = total / days;
  var day = 0;
  var dayWeight = 0;
  return [
    for (var index = 0; index < weights.length; index++)
      () {
        final weight = weights[index];
        final chunksIncludingCurrent = weights.length - index;
        final daySlotsIncludingCurrent = days - day;
        if (day < days - 1 &&
            dayWeight > 0 &&
            dayWeight + weight > target &&
            chunksIncludingCurrent >= daySlotsIncludingCurrent) {
          day++;
          dayWeight = 0;
        }
        dayWeight += weight;
        return day;
      }(),
  ];
}

int _weight(List<VerseUnit> units) => units.fold<int>(
  0,
  (total, unit) =>
      total + unit.text.replaceAll(RegExp(r'\s+'), '').runes.length,
);

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

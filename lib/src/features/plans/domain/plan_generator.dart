import '../../scripture/domain/scripture_models.dart';

final class GeneratedPlanTask {
  const GeneratedPlanTask({required this.dayIndex, required this.units});

  final int dayIndex;
  final List<VerseUnit> units;
}

final class PlanGenerator {
  const PlanGenerator();

  List<GeneratedPlanTask> generate({
    required List<VerseUnit> units,
    required int days,
  }) {
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'Must be positive');
    }
    if (units.isEmpty) {
      return const [];
    }

    final groupCount = days < units.length ? days : units.length;
    final weights = units.map((unit) => _weight(unit.text)).toList();
    final totalWeight = weights.fold<int>(0, (sum, value) => sum + value);
    final tasks = <GeneratedPlanTask>[];
    var cursor = 0;
    var consumedWeight = 0;

    for (var group = 0; group < groupCount; group++) {
      final remainingGroups = groupCount - group;
      final remainingUnits = units.length - cursor;
      final maxTake = remainingUnits - (remainingGroups - 1);
      final target = (totalWeight - consumedWeight) / remainingGroups;
      var take = 1;
      var weight = weights[cursor];
      while (take < maxTake) {
        final next = weights[cursor + take];
        if ((weight + next - target).abs() > (weight - target).abs()) break;
        weight += next;
        take++;
      }
      tasks.add(
        GeneratedPlanTask(
          dayIndex: groupCount == 1
              ? 0
              : (group * (days - 1) / (groupCount - 1)).round(),
          units: List.unmodifiable(units.sublist(cursor, cursor + take)),
        ),
      );
      cursor += take;
      consumedWeight += weight;
    }

    return List.unmodifiable(tasks);
  }

  int _weight(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return compact.isEmpty ? 1 : compact.runes.length;
  }
}

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
    if (days < 1 || days > 365) {
      throw ArgumentError.value(days, 'days', 'Must be between 1 and 365');
    }
    if (units.isEmpty) {
      return List.generate(
        days,
        (index) => GeneratedPlanTask(dayIndex: index, units: const []),
      );
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
          dayIndex: group,
          units: List.unmodifiable(units.sublist(cursor, cursor + take)),
        ),
      );
      cursor += take;
      consumedWeight += weight;
    }

    for (var day = groupCount; day < days; day++) {
      tasks.add(GeneratedPlanTask(dayIndex: day, units: const []));
    }
    return List.unmodifiable(tasks);
  }

  int _weight(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return compact.isEmpty ? 1 : compact.runes.length;
  }
}

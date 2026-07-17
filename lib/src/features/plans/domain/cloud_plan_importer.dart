import '../data/sqlite_plan_repository.dart';
import 'cloud_plan_manifest.dart';
import 'plan_models.dart';

final class CloudPlanImportResult {
  const CloudPlanImportResult({
    required this.inserted,
    required this.updated,
    required this.unchanged,
  });

  final int inserted;
  final int updated;
  final int unchanged;
}

final class CloudPlanImporter {
  const CloudPlanImporter();

  Future<CloudPlanImportResult> importPushed({
    required SqlitePlanRepository repository,
    required CloudPlanManifest manifest,
    required String sourceUrl,
    required DateTime today,
  }) async {
    var inserted = 0;
    var updated = 0;
    var unchanged = 0;
    for (final template in manifest.plans.where((plan) => plan.push)) {
      final existing = await repository.findPlanBySource(
        sourceUrl,
        template.id,
      );
      if (existing != null && existing.revision >= template.revision) {
        unchanged++;
        continue;
      }
      final start =
          existing?.startDate ?? template.defaultStartDate ?? _date(today);
      var end = existing?.endDate ?? template.defaultEndDate;
      final minimumEnd = start.add(
        Duration(days: template.passages.length - 1),
      );
      if (end == null || end.isBefore(minimumEnd)) end = minimumEnd;
      final translation =
          existing?.translationId ?? template.defaultTranslationId;
      final tasks = _tasks(template, start, end);
      final first = template.passages.first;
      final last = template.passages.last;
      final plan = NewMemorizationPlan(
        title: template.title,
        translationId: translation,
        bookId: first.bookId,
        startChapter: first.startChapter,
        endChapter: last.endChapter,
        startDate: start,
        endDate: end,
        tasks: tasks,
        sourceKind: PlanSourceKind.cloud,
        sourceUrl: sourceUrl,
        externalId: template.id,
        revision: template.revision,
        contentLocked: true,
      );
      if (existing == null) {
        await repository.createPlan(plan);
        inserted++;
      } else {
        await repository.updatePlan(existing.id, plan);
        updated++;
      }
    }
    return CloudPlanImportResult(
      inserted: inserted,
      updated: updated,
      unchanged: unchanged,
    );
  }

  List<NewPlanTask> _tasks(
    CloudPlanTemplate template,
    DateTime start,
    DateTime end,
  ) {
    final days = end.difference(start).inDays + 1;
    final count = template.passages.length;
    return [
      for (var index = 0; index < count; index++)
        NewPlanTask(
          dayIndex: count == 1 ? 0 : (index * (days - 1) / (count - 1)).round(),
          bookId: template.passages[index].bookId,
          startChapter: template.passages[index].startChapter,
          startVerse: template.passages[index].startVerse,
          endChapter: template.passages[index].endChapter,
          endVerse: template.passages[index].endVerse,
        ),
    ];
  }

  DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

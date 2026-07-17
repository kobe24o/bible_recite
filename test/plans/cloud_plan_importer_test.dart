import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/plans/domain/cloud_plan_importer.dart';
import 'package:bible_recite/src/features/plans/domain/cloud_plan_manifest.dart';
import 'package:bible_recite/src/features/plans/domain/plan_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'imports pushed cross-book plan once and never deletes local plans',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      await repository.createPlan(_localPlan());
      final manifest = CloudPlanManifest.parse(_manifest(revision: 1));

      final first = await const CloudPlanImporter().importPushed(
        repository: repository,
        manifest: manifest,
        sourceUrl: 'https://example.com/cloud-plans.json',
        today: DateTime(2026, 7, 17),
      );
      final second = await const CloudPlanImporter().importPushed(
        repository: repository,
        manifest: manifest,
        sourceUrl: 'https://example.com/cloud-plans.json',
        today: DateTime(2026, 7, 18),
      );

      expect(first.inserted, 1);
      expect(second.unchanged, 1);
      final plans = await repository.listPlans();
      expect(plans, hasLength(2));
      final cloud = plans.singleWhere(
        (plan) => plan.sourceKind == PlanSourceKind.cloud,
      );
      expect(cloud.contentLocked, isTrue);
      expect(
        (await repository.listTasks(cloud.id)).map((task) => task.bookId),
        ['GEN', 'JHN'],
      );
    },
  );

  test(
    'updates newer cloud content while preserving local dates and translation',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      const importer = CloudPlanImporter();
      const url = 'https://example.com/cloud-plans.json';
      await importer.importPushed(
        repository: repository,
        manifest: CloudPlanManifest.parse(_manifest(revision: 1)),
        sourceUrl: url,
        today: DateTime(2026, 7, 17),
      );
      final original = (await repository.listPlans()).single;
      final originalTasks = await repository.listTasks(original.id);
      await repository.updatePlan(
        original.id,
        NewMemorizationPlan(
          title: original.title,
          translationId: 'eng-web',
          bookId: original.bookId,
          startChapter: original.startChapter,
          endChapter: original.endChapter,
          startDate: DateTime(2026, 8, 1),
          endDate: DateTime(2026, 8, 2),
          tasks: [
            for (final task in originalTasks)
              NewPlanTask(
                dayIndex: task.dayIndex,
                bookId: task.bookId,
                startChapter: task.startChapter,
                startVerse: task.startVerse,
                endChapter: task.endChapter,
                endVerse: task.endVerse,
              ),
          ],
          sourceKind: original.sourceKind,
          sourceUrl: original.sourceUrl,
          externalId: original.externalId,
          revision: original.revision,
          contentLocked: true,
        ),
      );

      final result = await importer.importPushed(
        repository: repository,
        manifest: CloudPlanManifest.parse(_manifest(revision: 2, endVerse: 8)),
        sourceUrl: url,
        today: DateTime(2026, 9, 1),
      );

      expect(result.updated, 1);
      final updated = (await repository.listPlans()).single;
      expect(updated.translationId, 'eng-web');
      expect(updated.startDate, DateTime(2026, 8, 1));
      expect(updated.revision, 2);
      expect((await repository.listTasks(updated.id)).last.endVerse, 8);
    },
  );
}

String _manifest({required int revision, int endVerse = 5}) =>
    '''{
  "protocolVersion":1,
  "plans":[{
    "id":"cross-book","title":"跨卷计划","push":true,"revision":$revision,
    "defaultTranslationId":"cmn-cu89s",
    "passages":[
      {"order":1,"bookId":"GEN","startChapter":1,"startVerse":1,"endChapter":1,"endVerse":3},
      {"order":2,"bookId":"JHN","startChapter":1,"startVerse":1,"endChapter":1,"endVerse":$endVerse}
    ]
  }]
}''';

NewMemorizationPlan _localPlan() => NewMemorizationPlan(
  title: '本地计划',
  translationId: 'cmn-cu89s',
  bookId: 'PSA',
  startChapter: 23,
  endChapter: 23,
  startDate: DateTime(2026, 7, 17),
  endDate: DateTime(2026, 7, 17),
  tasks: const [
    NewPlanTask(
      dayIndex: 0,
      startChapter: 23,
      startVerse: 1,
      endChapter: 23,
      endVerse: 6,
    ),
  ],
);

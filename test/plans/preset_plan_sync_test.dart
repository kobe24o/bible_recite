import 'package:bible_recite/src/features/plans/application/preset_plan_sync.dart';
import 'package:bible_recite/src/features/plans/data/cloud_plan_feed_client.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'caches remote preset plans and clears NEW after a user opens one',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final client = CloudPlanFeedClient(loader: (_) async => _manifest(1));

      final first = await syncPresetPlans(
        repository: repository,
        client: client,
      );

      expect(first.newPlanIds, {'hope'});
      expect(
        (await loadCachedPresetPlanManifest(repository))?.plans.single.id,
        'hope',
      );
      await markPresetPlanSeen(repository, 'hope');
      expect(await loadNewPresetPlanIds(repository), isEmpty);

      final unchanged = await syncPresetPlans(
        repository: repository,
        client: client,
      );
      expect(unchanged.newPlanIds, isEmpty);

      final upgraded = await syncPresetPlans(
        repository: repository,
        client: CloudPlanFeedClient(loader: (_) async => _manifest(2)),
      );
      expect(upgraded.newPlanIds, {'hope'});
    },
  );
}

String _manifest(int revision) =>
    '''{
  "protocolVersion": 1,
  "plans": [{
    "id": "hope",
    "title": "盼望",
    "revision": $revision,
    "defaultTranslationId": "cmn-cu89s",
    "passages": [{
      "order": 1,
      "bookId": "JHN",
      "startChapter": 3,
      "startVerse": 16,
      "endChapter": 3,
      "endVerse": 16
    }]
  }]
}''';

import 'package:bible_recite/src/features/devotion/application/devotion_providers.dart';
import 'package:bible_recite/src/features/devotion/data/devotion_feed_client.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'devotion_models_test.dart' show complete2026Json;

void main() {
  late SqlitePlanRepository repository;

  setUp(() {
    repository = SqlitePlanRepository(sqlite3.openInMemory());
  });

  tearDown(() => repository.close());

  test('keeps the prior cache when a new feed is invalid', () async {
    await repository.cacheDevotionManifest(complete2026Json);

    await expectLater(
      repository.cacheDevotionManifest('{'),
      throwsFormatException,
    );

    expect((await repository.loadCachedDevotionManifest())!.revision, 1);
  });

  test('ignores an invalid legacy cached manifest', () async {
    await repository.setSetting(devotionManifestSettingKey, '{');

    expect(await repository.loadCachedDevotionManifest(), isNull);
  });

  test('upserts a note by normalized calendar day', () async {
    final day = DateTime(2026, 9, 17, 18, 45);
    final firstUpdatedAt = DateTime.utc(2026, 9, 17, 8);
    final secondUpdatedAt = DateTime.utc(2026, 9, 17, 9, 30);

    await repository.saveDevotionNote(day, '今天的领受', updatedAt: firstUpdatedAt);
    await repository.saveDevotionNote(
      DateTime(2026, 9, 17),
      '',
      updatedAt: secondUpdatedAt,
    );

    final note = (await repository.devotionNoteFor(day))!;
    expect(note.content, isEmpty);
    expect(note.updatedAt, secondUpdatedAt);
  });

  test('syncs a validated feed before notifying the UI', () async {
    var callbackSawCachedManifest = false;

    final manifest = await syncDevotionManifest(
      repository: repository,
      client: DevotionFeedClient(loader: (_) async => complete2026Json),
      onCached: () async {
        callbackSawCachedManifest =
            await repository.loadCachedDevotionManifest() != null;
      },
    );

    expect(manifest.revision, 1);
    expect(callbackSawCachedManifest, isTrue);
  });
}

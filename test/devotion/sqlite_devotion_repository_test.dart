import 'dart:convert';

import 'package:bible_recite/src/features/devotion/application/devotion_providers.dart';
import 'package:bible_recite/src/features/devotion/data/devotion_feed_client.dart';
import 'package:bible_recite/src/features/devotion/domain/devotion_models.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'devotion_models_test.dart' show complete2026Json;

void main() {
  late SqlitePlanRepository repository;

  test('today provider exposes an exact calendar day', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final now = DateTime.now();

    expect(
      container.read(devotionTodayProvider),
      DateTime(now.year, now.month, now.day),
    );
  });

  test('today provider refreshes a retained container across dates', () {
    var now = DateTime(2026, 9, 17, 23, 59);
    final container = ProviderContainer(
      overrides: [devotionClockProvider.overrideWithValue(() => now)],
    );
    addTearDown(container.dispose);

    expect(container.read(devotionTodayProvider), DateTime(2026, 9, 17));
    now = DateTime(2026, 9, 18, 0, 1);
    container.read(devotionTodayProvider.notifier).refresh();
    expect(container.read(devotionTodayProvider), DateTime(2026, 9, 18));
  });

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

  test('keeps only non-empty notes by normalized calendar day', () async {
    final day = DateTime(2026, 9, 17, 18, 45);
    final firstUpdatedAt = DateTime.utc(2026, 9, 17, 8);
    final secondUpdatedAt = DateTime.utc(2026, 9, 17, 9, 30);

    await repository.saveDevotionNote(day, '今天的领受', updatedAt: firstUpdatedAt);
    await repository.saveDevotionNote(
      DateTime(2026, 9, 17),
      '',
      updatedAt: secondUpdatedAt,
    );

    expect(await repository.devotionNoteFor(day), isNull);
    expect(await repository.listDevotionNotes(), isEmpty);
  });

  test(
    'lists written notes by calendar date and excludes blank rows',
    () async {
      await repository.saveDevotionNote(DateTime(2026, 9, 19), '后来写的');
      await repository.saveDevotionNote(DateTime(2026, 9, 17), '较早写的');
      await repository.saveDevotionNote(DateTime(2026, 9, 18), '   ');

      final notes = await repository.listDevotionNotes();

      expect(notes.map((note) => note.date), [
        DateTime(2026, 9, 17),
        DateTime(2026, 9, 19),
      ]);
      expect(notes.map((note) => note.content), ['较早写的', '后来写的']);
    },
  );

  test('stores a snapshot of a written notes scripture references', () async {
    const passages = [
      DevotionPassage(
        bookId: 'JHN',
        startChapter: 3,
        startVerse: 16,
        endChapter: 4,
        endVerse: 3,
      ),
    ];
    await repository.saveDevotionNote(
      DateTime(2026, 9, 17),
      '神爱世人',
      passages: passages,
    );

    final note = (await repository.devotionNoteFor(DateTime(2026, 9, 17)))!;

    expect(note.passages.single.bookId, 'JHN');
    expect(note.passages.single.startChapter, 3);
    expect(note.passages.single.endChapter, 4);
    expect(note.passages.single.endVerse, 3);
  });

  test(
    'sync caches the exact validated feed before notifying the UI',
    () async {
      var callbackSawCachedManifest = false;
      final payload = jsonDecode(complete2026Json) as Map<String, Object?>;
      payload['publisherNote'] =
          'metadata that the schedule model does not use';
      final originalSource =
          '\n${const JsonEncoder.withIndent('  ').convert(payload)}\n';

      final manifest = await syncDevotionManifest(
        repository: repository,
        client: DevotionFeedClient(loader: (_) async => originalSource),
        onCached: () async {
          callbackSawCachedManifest =
              await repository.loadCachedDevotionManifest() != null;
        },
      );

      expect(manifest.revision, 1);
      expect(manifest.dayFor(DateTime(2026, 2, 2))!.passages, hasLength(2));
      expect(
        await repository.getSetting(devotionManifestSettingKey, ''),
        originalSource,
      );
      expect(callbackSawCachedManifest, isTrue);
    },
  );

  test('a failed sync preserves the last valid cache', () async {
    await repository.cacheDevotionManifest(complete2026Json);

    await expectLater(
      syncDevotionManifest(
        repository: repository,
        client: DevotionFeedClient(loader: (_) async => '{'),
      ),
      throwsA(isA<DevotionFeedException>()),
    );

    expect(
      await repository.getSetting(devotionManifestSettingKey, ''),
      complete2026Json,
    );
  });
}

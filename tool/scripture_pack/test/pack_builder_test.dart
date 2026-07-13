// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../lib/canon_validator.dart';
import '../lib/pack_builder.dart';
import '../lib/parallel_mapping_builder.dart';
import '../lib/source_fetcher.dart';
import '../lib/verse_unit_assembler.dart';

void main() {
  test('builds a queryable pack and records source provenance', () async {
    final parent = await Directory.systemTemp.createTemp('scripture-pack-');
    addTearDown(() => parent.delete(recursive: true));
    final output = Directory('${parent.path}${Platform.pathSeparator}fixture');

    await PackBuilder().build(
      output: output,
      source: fixtureSource,
      units: const [
        ParsedVerseUnit(
          sourceOrder: 0,
          sourceVerseId: 'GEN1_1',
          bookCode: 'GEN',
          chapter: 1,
          startVerse: 1,
          endVerse: 1,
          text: 'In the beginning.',
          status: SourceTextStatus.present,
        ),
      ],
      canon: CanonDefinition(
        canonId: 'fixture-canon',
        books: const [CanonBook(code: 'GEN', chapterCount: 1)],
      ),
    );

    final database = sqlite3.open(
      '${output.path}${Platform.pathSeparator}scripture.sqlite',
    );
    addTearDown(database.close);
    expect(
      database.select('SELECT text FROM verse_unit').single['text'],
      'In the beginning.',
    );
    expect(
      database.select('PRAGMA integrity_check').single.values.single,
      'ok',
    );

    final manifest =
        jsonDecode(
              await File(
                '${output.path}${Platform.pathSeparator}manifest.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    expect(
      (manifest['source'] as Map<String, Object?>)['archiveSha256'],
      fixtureSource.sha256,
    );
    expect(manifest['schemaVersion'], 1);
    expect(
      (manifest['translation'] as Map<String, Object?>)['versificationId'],
      isNotEmpty,
    );
    expect(
      File('${output.path}${Platform.pathSeparator}LICENSE.txt').existsSync(),
      isTrue,
    );
  });

  test(
    'produces identical sqlite bytes for identical semantic input',
    () async {
      final parent = await Directory.systemTemp.createTemp('scripture-pack-');
      addTearDown(() => parent.delete(recursive: true));
      final canon = CanonDefinition(
        canonId: 'fixture-canon',
        books: const [CanonBook(code: 'GEN', chapterCount: 1)],
      );
      const units = [
        ParsedVerseUnit(
          sourceOrder: 0,
          sourceVerseId: 'GEN1_1',
          bookCode: 'GEN',
          chapter: 1,
          startVerse: 1,
          endVerse: 2,
          text: 'Bridge text.',
          status: SourceTextStatus.present,
        ),
      ];

      final first = Directory('${parent.path}${Platform.pathSeparator}first');
      final second = Directory('${parent.path}${Platform.pathSeparator}second');
      await PackBuilder().build(
        output: first,
        source: fixtureSource,
        units: units,
        canon: canon,
      );
      await PackBuilder().build(
        output: second,
        source: fixtureSource,
        units: units,
        canon: canon,
      );

      expect(
        File(
          '${first.path}${Platform.pathSeparator}scripture.sqlite',
        ).readAsBytesSync(),
        File(
          '${second.path}${Platform.pathSeparator}scripture.sqlite',
        ).readAsBytesSync(),
      );
    },
  );

  test('stores content-bound parallel groups in both directions', () async {
    final parent = await Directory.systemTemp.createTemp('scripture-pack-');
    addTearDown(() => parent.delete(recursive: true));
    final output = Directory('${parent.path}${Platform.pathSeparator}fixture');
    final canon = CanonDefinition(
      canonId: 'fixture-canon',
      books: const [CanonBook(code: 'GEN', chapterCount: 1)],
    );
    const sourceUnits = [
      ParsedVerseUnit(
        sourceOrder: 0,
        sourceVerseId: 'GEN1_1',
        bookCode: 'GEN',
        chapter: 1,
        startVerse: 1,
        endVerse: 2,
        text: 'Bridge text.',
        status: SourceTextStatus.present,
      ),
    ];
    final sourceHash = await computeSemanticSha256(
      source: fixtureSource,
      canon: canon,
      units: sourceUnits,
    );
    final mapping = ParallelMappingBuilder().build(
      sourceTranslationId: fixtureSource.id,
      sourceSemanticSha256: sourceHash,
      sourceUnits: sourceUnits,
      targetTranslationId: 'target',
      targetSemanticSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      targetUnits: const [
        ParsedVerseUnit(
          sourceOrder: 0,
          sourceVerseId: 'GEN1_1',
          bookCode: 'GEN',
          chapter: 1,
          startVerse: 1,
          endVerse: 1,
          text: 'One.',
          status: SourceTextStatus.present,
        ),
        ParsedVerseUnit(
          sourceOrder: 1,
          sourceVerseId: 'GEN1_2',
          bookCode: 'GEN',
          chapter: 1,
          startVerse: 2,
          endVerse: 2,
          text: 'Two.',
          status: SourceTextStatus.present,
        ),
      ],
      overrides: const [],
    );
    await PackBuilder().build(
      output: output,
      source: fixtureSource,
      units: sourceUnits,
      canon: canon,
      parallelMappings: [mapping],
    );

    final database = sqlite3.open(
      '${output.path}${Platform.pathSeparator}scripture.sqlite',
    );
    addTearDown(database.close);
    expect(
      database
          .select('SELECT COUNT(*) count FROM parallel_group')
          .single['count'],
      1,
    );
    expect(
      database
          .select('SELECT COUNT(*) count FROM parallel_target_member')
          .single['count'],
      2,
    );
  });
}

final fixtureSource = SourceDescriptor(
  id: 'fixture',
  name: 'Fixture Bible',
  languageTag: 'en',
  detailsUrl: Uri.parse('https://example.test/fixture'),
  archiveUrl: Uri.parse('https://example.test/fixture.zip'),
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  licenseId: 'public-domain',
);

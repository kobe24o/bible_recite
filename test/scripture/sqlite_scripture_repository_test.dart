import 'dart:io';

import 'package:bible_recite/src/features/scripture/data/sqlite_scripture_repository.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteScriptureRepository repository;

  setUpAll(() async {
    final registry = await ScripturePackRegistry.fromDirectories({
      for (final id in ['cmn-cu89s', 'cmn-cu89t', 'eng-web'])
        id: Directory('assets/scripture/$id'),
    });
    repository = SqliteScriptureRepository(registry: registry);
  });

  test('reads John 3:16 through a text unit and stable verse slot', () async {
    final units = await repository.getChapter('eng-web', 'JHN', 3);
    final verse = units.singleWhere((unit) => unit.start.verse == 16);
    expect(verse.start.osisBookId, 'JHN');
    expect(verse.text, contains('For God so loved the world'));
  });

  test(
    'loads chapter verse totals for achievement progress in one query',
    () async {
      final totals = await repository.getChapterVerseCounts('cmn-cu89s');

      expect(totals['JHN:3'], 36);
      expect(totals['GEN:1'], 31);
      expect(totals['REV:22'], 21);
    },
  );

  test('keeps Genesis 11:6–12:7 as its exact 34-verse passage', () async {
    final passage = await repository.getPassage(
      'cmn-cu89s',
      PassageRange(
        start: (
          canonId: CanonId.protestant66,
          osisBookId: 'GEN',
          chapter: 11,
          verse: 6,
        ),
        end: (
          canonId: CanonId.protestant66,
          osisBookId: 'GEN',
          chapter: 12,
          verse: 7,
        ),
      ),
    );

    expect(passage.units, hasLength(34));
    expect(passage.units.first.start.chapter, 11);
    expect(passage.units.first.start.verse, 6);
    expect(passage.units.last.end.chapter, 12);
    expect(passage.units.last.end.verse, 7);
  });

  test('parallel repository returns an approved cross-chapter group', () async {
    final range = PassageRange(
      start: (
        canonId: CanonId.protestant66,
        osisBookId: 'REV',
        chapter: 12,
        verse: 18,
      ),
      end: (
        canonId: CanonId.protestant66,
        osisBookId: 'REV',
        chapter: 13,
        verse: 1,
      ),
    );
    final result = await repository.resolveParallelPassage(
      LocatedPassageRange(translationId: 'cmn-cu89s', range: range),
      'eng-web',
    );
    final group = result.groups.singleWhere(
      (candidate) =>
          candidate.relation == ParallelRelation.crossChapterTargetBridge,
    );
    expect(group.targetUnits.single.start.chapter, 13);
    expect(group.targetUnits.single.start.verse, 1);
  });
}

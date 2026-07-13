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

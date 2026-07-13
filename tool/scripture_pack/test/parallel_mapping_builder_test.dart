// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:test/test.dart';

import '../lib/parallel_mapping_builder.dart';
import '../lib/parallel_mapping_validator.dart';
import '../lib/verse_unit_assembler.dart';

void main() {
  test(
    'resolves bridges, cross-chapter bridges, and relocated doxology in both directions',
    () {
      final builder = ParallelMappingBuilder();
      final mapping = builder.build(
        sourceTranslationId: 'cmn-cu89s',
        sourceSemanticSha256: _hash('a'),
        sourceUnits: [
          _unit(0, 'GEN', 24, 29, 30),
          _unit(1, 'REV', 12, 18, 18),
          _unit(2, 'REV', 13, 1, 1),
          _unit(3, 'ROM', 16, 25, 25),
          _unit(4, 'ROM', 16, 26, 26),
          _unit(5, 'ROM', 16, 27, 27),
        ],
        targetTranslationId: 'eng-web',
        targetSemanticSha256: _hash('b'),
        targetUnits: [
          _unit(0, 'GEN', 24, 29, 29),
          _unit(1, 'GEN', 24, 30, 30),
          _unit(2, 'REV', 13, 1, 1),
          _unit(3, 'ROM', 14, 24, 24),
          _unit(4, 'ROM', 14, 25, 25),
          _unit(5, 'ROM', 14, 26, 26),
        ],
        overrides: [
          ParallelMappingOverride(
            sourceKeys: const ['REV.12.18', 'REV.13.1'],
            targetKeys: const ['REV.13.1'],
            relation: ParallelRelation.crossChapterTargetBridge,
            evidence: 'Reviewed against the pinned source editions.',
          ),
          ParallelMappingOverride(
            sourceKeys: const ['ROM.16.25', 'ROM.16.26', 'ROM.16.27'],
            targetKeys: const ['ROM.14.24', 'ROM.14.25', 'ROM.14.26'],
            relation: ParallelRelation.relocated,
            evidence: 'Reviewed versification relocation.',
          ),
        ],
      );

      expect(mapping.groupForSource('GEN.24.29')!.targetKeys, [
        'GEN.24.29',
        'GEN.24.30',
      ]);
      expect(mapping.groupForSource('REV.12.18')!.targetKeys, ['REV.13.1']);
      expect(mapping.groupForSource('ROM.16.25')!.targetKeys, [
        'ROM.14.24',
        'ROM.14.25',
        'ROM.14.26',
      ]);
      for (final group in mapping.groups) {
        for (final key in group.sourceKeys) {
          expect(mapping.groupForSource(key), same(group));
        }
        for (final key in group.targetKeys) {
          expect(mapping.groupForTarget(key), same(group));
        }
      }
      expect(mapping.unresolvedSourceKeys, isEmpty);
      expect(mapping.unresolvedTargetKeys, isEmpty);
    },
  );

  test('requires an explicit absence reason for a present unmatched unit', () {
    final mapping = ParallelMappingBuilder().build(
      sourceTranslationId: 'cmn-cu89s',
      sourceSemanticSha256: _hash('a'),
      sourceUnits: [_unit(0, 'JHN', 5, 3, 3)],
      targetTranslationId: 'eng-web',
      targetSemanticSha256: _hash('b'),
      targetUnits: [_unit(0, 'JHN', 5, 4, 4)],
      overrides: [
        ParallelMappingOverride(
          sourceKeys: const [],
          targetKeys: const ['JHN.5.4'],
          relation: ParallelRelation.sourceAbsent,
          evidence: 'Verse is absent from the CUV source.',
        ),
        ParallelMappingOverride(
          sourceKeys: const ['JHN.5.3'],
          targetKeys: const [],
          relation: ParallelRelation.targetAbsent,
          evidence: 'Verse is absent from the WEB source.',
        ),
      ],
    );

    expect(mapping.unresolvedSourceKeys, isEmpty);
    expect(mapping.unresolvedTargetKeys, isEmpty);
    expect(
      mapping.groupForTarget('JHN.5.4')!.relation,
      ParallelRelation.sourceAbsent,
    );
    expect(() => ParallelMappingValidator().validate(mapping), returnsNormally);
  });

  test('validator rejects unresolved units', () {
    final mapping = ParallelMappingBuilder().build(
      sourceTranslationId: 'cmn-cu89s',
      sourceSemanticSha256: _hash('a'),
      sourceUnits: [_unit(0, 'GEN', 1, 1, 1)],
      targetTranslationId: 'eng-web',
      targetSemanticSha256: _hash('b'),
      targetUnits: const [],
      overrides: const [],
    );

    expect(
      () => ParallelMappingValidator().validate(mapping),
      throwsA(isA<ParallelMappingValidationException>()),
    );
  });

  test('reviewed overrides are bound to exact semantic hashes', () async {
    final catalog = await ReviewedOverrideCatalog.load(
      File('assets/scripture/versification/parallel_overrides.json'),
    );

    expect(
      catalog
          .requireExact(
            sourceTranslationId: 'cmn-cu89s',
            sourceSemanticSha256:
                '79f59350deb4651b7a194c33b176b1a4cde35c0207e7c4f4d7a3e95b42acedb0',
            targetTranslationId: 'eng-web',
            targetSemanticSha256:
                'f76e1422302bf3e3d541092c057c3308bdba15e1459dda745a1ad7063e57fe7a',
          )
          .overrides,
      hasLength(18),
    );
    expect(
      () => catalog.requireExact(
        sourceTranslationId: 'cmn-cu89s',
        sourceSemanticSha256: _hash('0'),
        targetTranslationId: 'eng-web',
        targetSemanticSha256: _hash('b'),
      ),
      throwsStateError,
    );
  });
}

ParsedVerseUnit _unit(int order, String book, int chapter, int start, int end) {
  return ParsedVerseUnit(
    sourceOrder: order,
    sourceVerseId: '$book${chapter}_$start',
    bookCode: book,
    chapter: chapter,
    startVerse: start,
    endVerse: end,
    text: 'text',
    status: SourceTextStatus.present,
  );
}

String _hash(String character) => character * 64;

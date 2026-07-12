import 'dart:io';

import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:test/test.dart';

// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/canon_validator.dart';
// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/ebible_vpl_source_adapter.dart';
// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/scripture_source_adapter.dart';
// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/source_fetcher.dart';

void main() {
  late CanonDefinition canon;
  late SourceCatalog catalog;

  setUpAll(() async {
    canon = await CanonDefinition.load(
      File('assets/scripture/canon/protestant66.json'),
    );
    catalog = await SourceCatalog.load(
      File('tool/scripture_pack/source_catalog.json'),
    );
  });

  for (final translationId in ['cmn-cu89s', 'cmn-cu89t']) {
    test('$translationId preserves all CUV bridge units and slots', () async {
      final descriptor = catalog.sources.singleWhere(
        (source) => source.id == translationId,
      );
      final normalized = await EbibleVplSourceAdapter().parse(
        bundleFor(descriptor),
      );
      final validated = CanonValidator().validate(
        canon: canon,
        units: normalized.units,
        slots: normalized.slots,
        filterNonCanon: true,
      );

      expect(validated.units, hasLength(31021));
      expect(validated.slots, hasLength(31092));
      expect(validated.bridgeUnitCount, 70);
      expect(validated.extraBridgeSlotCount, 71);
      expect(validated.omittedSlotCount, 0);
    });
  }

  test(
    'WEB filters to 66 books and preserves exactly five omissions',
    () async {
      final descriptor = catalog.sources.singleWhere(
        (source) => source.id == 'eng-web',
      );
      final normalized = await EbibleVplSourceAdapter().parse(
        bundleFor(descriptor),
      );
      final validated = CanonValidator().validate(
        canon: canon,
        units: normalized.units,
        slots: normalized.slots,
        filterNonCanon: true,
      );

      expect(validated.units, hasLength(31103));
      expect(validated.slots, hasLength(31103));
      expect(validated.omittedSlotCount, 5);
      final omitted = validated.units
          .where((unit) => unit.status == SourceTextStatus.omitted)
          .map((unit) => '${unit.bookCode}.${unit.chapter}.${unit.startVerse}')
          .toList(growable: false);
      expect(omitted, [
        'LUK.17.36',
        'ACT.8.37',
        'ACT.15.34',
        'ACT.24.7',
        'ROM.16.25',
      ]);
    },
  );

  test('SQL envelope rejects an unexpected executable statement', () {
    expect(
      () => EbibleSqlEnvelope.extractInsertLines(
        expectedTableName: 'fixture_vpl',
        lines: const ['USE sofia;', 'DROP TABLE other;'],
      ),
      throwsFormatException,
    );
  });
}

SourceBundle bundleFor(SourceDescriptor source) {
  return SourceBundle(
    archive: File('tool/scripture_pack/.cache/${source.id}_vpl.zip'),
    translation: NormalizedTranslationMetadata(
      id: source.id,
      name: source.name,
      languageTag: source.languageTag,
      licenseId: source.licenseId,
    ),
    provenance: SourceProvenance(
      detailsUrl: source.detailsUrl!,
      archiveUrl: source.archiveUrl,
      archiveSha256: source.sha256,
    ),
  );
}

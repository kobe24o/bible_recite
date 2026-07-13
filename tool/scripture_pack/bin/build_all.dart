// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:cryptography/cryptography.dart';

import '../lib/canon_validator.dart';
import '../lib/ebible_vpl_source_adapter.dart';
import '../lib/pack_builder.dart';
import '../lib/parallel_mapping_builder.dart';
import '../lib/parallel_mapping_validator.dart';
import '../lib/scripture_source_adapter.dart';
import '../lib/source_fetcher.dart';
import '../lib/verse_unit_assembler.dart';

Future<void> main() async {
  final root = Directory.current;
  final catalog = await SourceCatalog.load(
    File('${root.path}/tool/scripture_pack/source_catalog.json'),
  );
  final canon = await CanonDefinition.load(
    File('${root.path}/assets/scripture/canon/protestant66.json'),
  );
  final cache = Directory('${root.path}/tool/scripture_pack/.cache');
  final adapter = EbibleVplSourceAdapter();
  final normalized = <String, _BuildInput>{};

  for (final descriptor in catalog.sources) {
    final archive = await SourceFetcher().fetch(descriptor, cache);
    final parsed = await adapter.parse(
      SourceBundle(
        archive: archive,
        translation: NormalizedTranslationMetadata(
          id: descriptor.id,
          name: descriptor.name,
          languageTag: descriptor.languageTag,
          licenseId: descriptor.licenseId,
        ),
        provenance: SourceProvenance(
          detailsUrl: descriptor.detailsUrl!,
          archiveUrl: descriptor.archiveUrl,
          archiveSha256: descriptor.sha256,
        ),
      ),
    );
    final validated = CanonValidator().validate(
      canon: canon,
      units: parsed.units,
      slots: parsed.slots,
      filterNonCanon: true,
    );
    final semanticSha256 = await computeSemanticSha256(
      source: descriptor,
      canon: canon,
      units: validated.units,
    );
    normalized[descriptor.id] = _BuildInput(
      descriptor: descriptor,
      units: validated.units,
      semanticSha256: semanticSha256,
      sourceEvidence: await _readSourceEvidence(archive, descriptor.id),
    );
    stdout.writeln(
      '${descriptor.id}: units=${validated.units.length}, '
      'slots=${validated.slots.length}, bridges=${validated.bridgeUnitCount}, '
      'omitted=${validated.omittedSlotCount}, semantic=$semanticSha256',
    );
  }

  final mappingsBySource = <String, List<ParallelMappingResult>>{
    for (final id in normalized.keys) id: <ParallelMappingResult>[],
  };
  final reviewedCatalog = await ReviewedOverrideCatalog.load(
    File('${root.path}/assets/scripture/versification/parallel_overrides.json'),
  );
  void addMapping(String sourceId, String targetId) {
    final source = normalized[sourceId]!;
    final target = normalized[targetId]!;
    final forwardOverrides = _reviewedOverrides(
      reviewedCatalog,
      source,
      target,
    );
    final mapping = ParallelMappingBuilder().build(
      sourceTranslationId: sourceId,
      sourceSemanticSha256: source.semanticSha256,
      sourceUnits: source.units,
      targetTranslationId: targetId,
      targetSemanticSha256: target.semanticSha256,
      targetUnits: target.units,
      overrides: forwardOverrides,
    );
    ParallelMappingValidator().validate(mapping);
    mappingsBySource[sourceId]!.add(mapping);
    stdout.writeln(
      '$sourceId -> $targetId: groups=${mapping.groups.length}, '
      'unresolvedSource=${mapping.unresolvedSourceKeys.length}, '
      'unresolvedTarget=${mapping.unresolvedTargetKeys.length}',
    );
  }

  addMapping('cmn-cu89s', 'cmn-cu89t');
  addMapping('cmn-cu89t', 'cmn-cu89s');
  addMapping('cmn-cu89s', 'eng-web');
  addMapping('cmn-cu89t', 'eng-web');
  addMapping('eng-web', 'cmn-cu89s');
  addMapping('eng-web', 'cmn-cu89t');

  for (final input in normalized.values) {
    final result = await PackBuilder().build(
      output: Directory('${root.path}/assets/scripture/${input.descriptor.id}'),
      source: input.descriptor,
      units: input.units,
      canon: canon,
      parallelMappings: mappingsBySource[input.descriptor.id]!,
      sourceEvidence: input.sourceEvidence,
    );
    stdout.writeln(
      '${input.descriptor.id}: sqlite=${result.sqliteSha256}, integrity=ok',
    );
  }
  await _writeIndex(root, normalized.keys);
}

List<ParallelMappingOverride> _reviewedOverrides(
  ReviewedOverrideCatalog catalog,
  _BuildInput source,
  _BuildInput target,
) {
  if (source.descriptor.id.startsWith('cmn-cu89') &&
      target.descriptor.id == 'eng-web') {
    return catalog
        .requireExact(
          sourceTranslationId: source.descriptor.id,
          sourceSemanticSha256: source.semanticSha256,
          targetTranslationId: target.descriptor.id,
          targetSemanticSha256: target.semanticSha256,
        )
        .overrides;
  }
  if (source.descriptor.id == 'eng-web' &&
      target.descriptor.id.startsWith('cmn-cu89')) {
    return catalog
        .requireExact(
          sourceTranslationId: target.descriptor.id,
          sourceSemanticSha256: target.semanticSha256,
          targetTranslationId: source.descriptor.id,
          targetSemanticSha256: source.semanticSha256,
        )
        .overrides
        .map(_reverseOverride)
        .toList(growable: false);
  }
  return const [];
}

ParallelMappingOverride _reverseOverride(ParallelMappingOverride value) {
  final relation = switch (value.relation) {
    ParallelRelation.sourceAbsent => ParallelRelation.targetAbsent,
    ParallelRelation.targetAbsent => ParallelRelation.sourceAbsent,
    ParallelRelation.sourceBridge => ParallelRelation.targetBridge,
    ParallelRelation.targetBridge => ParallelRelation.sourceBridge,
    ParallelRelation.crossChapterTargetBridge => ParallelRelation.sourceBridge,
    _ => value.relation,
  };
  return ParallelMappingOverride(
    sourceKeys: value.targetKeys,
    targetKeys: value.sourceKeys,
    relation: relation,
    evidence: value.evidence,
  );
}

Future<void> _writeIndex(
  Directory root,
  Iterable<String> translationIds,
) async {
  final entries = <Map<String, Object?>>[];
  for (final id in translationIds) {
    final manifest = File('${root.path}/assets/scripture/$id/manifest.json');
    entries.add({
      'manifestSha256': await _hashFile(manifest),
      'translationId': id,
    });
  }
  entries.sort(
    (left, right) => (left['translationId']! as String).compareTo(
      right['translationId']! as String,
    ),
  );
  await File('${root.path}/assets/scripture/index.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'packs': entries, 'schemaVersion': 1})}\n',
    flush: true,
  );
}

Future<String> _hashFile(File file) async {
  final sink = Sha256().newHashSink();
  await for (final chunk in file.openRead()) {
    sink.add(chunk);
  }
  sink.close();
  return (await sink.hash()).bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

Future<PackSourceEvidence> _readSourceEvidence(
  File archiveFile,
  String translationId,
) async {
  final archive = ZipDecoder().decodeBytes(
    await archiveFile.readAsBytes(),
    verify: true,
  );
  final text = archive.find('${translationId}_vpl.txt');
  final about = archive.find('${translationId}_about.htm');
  if (text == null || !text.isFile || about == null || !about.isFile) {
    throw FormatException(
      'Source evidence files are missing for $translationId',
    );
  }
  return PackSourceEvidence(
    textSha256: await _hashBytes(text.content),
    aboutSha256: await _hashBytes(about.content),
    retrievalDate: '2026-07-12',
    additionalLicenseNotice: translationId == 'eng-web'
        ? 'The World English Bible is Public Domain. "World English Bible" '
              'is a trademark of eBible.org; modified text must not retain that name.'
        : '',
  );
}

Future<String> _hashBytes(List<int> bytes) async {
  return (await Sha256().hash(
    bytes,
  )).bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

final class _BuildInput {
  const _BuildInput({
    required this.descriptor,
    required this.units,
    required this.semanticSha256,
    required this.sourceEvidence,
  });

  final SourceDescriptor descriptor;
  final List<ParsedVerseUnit> units;
  final String semanticSha256;
  final PackSourceEvidence sourceEvidence;
}

import 'dart:io';

import 'verse_unit_assembler.dart';

abstract interface class ScriptureSourceAdapter {
  String get formatId;

  Future<NormalizedScriptureSource> parse(SourceBundle source);
}

final class SourceBundle {
  const SourceBundle({
    required this.archive,
    required this.translation,
    required this.provenance,
  });

  final File archive;
  final NormalizedTranslationMetadata translation;
  final SourceProvenance provenance;
}

final class NormalizedTranslationMetadata {
  const NormalizedTranslationMetadata({
    required this.id,
    required this.name,
    required this.languageTag,
    required this.licenseId,
  });

  final String id;
  final String name;
  final String languageTag;
  final String licenseId;
}

final class SourceProvenance {
  const SourceProvenance({
    required this.detailsUrl,
    required this.archiveUrl,
    required this.archiveSha256,
  });

  final Uri detailsUrl;
  final Uri archiveUrl;
  final String archiveSha256;
}

final class NormalizedScriptureSource {
  NormalizedScriptureSource({
    required this.translation,
    required List<ParsedVerseUnit> units,
    required List<ParsedVerseSlot> slots,
    required this.provenance,
  }) : units = List.unmodifiable(units),
       slots = List.unmodifiable(slots);

  final NormalizedTranslationMetadata translation;
  final List<ParsedVerseUnit> units;
  final List<ParsedVerseSlot> slots;
  final SourceProvenance provenance;
}

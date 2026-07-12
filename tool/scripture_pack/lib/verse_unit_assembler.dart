import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';

import 'book_code_map.dart';
import 'vpl_parser.dart';
import 'vpl_sql_metadata_parser.dart';

typedef _VerseAddress = ({String bookCode, int chapter, int verse});

final class ParsedVerseUnit {
  const ParsedVerseUnit({
    required this.sourceOrder,
    required this.sourceVerseId,
    required this.bookCode,
    required this.chapter,
    required this.startVerse,
    required this.endVerse,
    required this.text,
    required this.status,
  });

  final int sourceOrder;
  final String? sourceVerseId;
  final String bookCode;
  final int chapter;
  final int startVerse;
  final int endVerse;
  final String text;
  final SourceTextStatus status;
}

final class ParsedVerseSlot {
  const ParsedVerseSlot({
    required this.bookCode,
    required this.chapter,
    required this.verse,
    required this.unitOrdinal,
  });

  final String bookCode;
  final int chapter;
  final int verse;
  final int unitOrdinal;
}

final class VerseAssemblyResult {
  VerseAssemblyResult({
    required List<ParsedVerseUnit> units,
    required List<ParsedVerseSlot> slots,
  }) : units = List.unmodifiable(units),
       slots = List.unmodifiable(slots);

  final List<ParsedVerseUnit> units;
  final List<ParsedVerseSlot> slots;
}

final class VerseAssemblyException implements Exception {
  const VerseAssemblyException(this.message);

  final String message;

  @override
  String toString() => 'VerseAssemblyException: $message';
}

final class VerseUnitAssembler {
  VerseAssemblyResult assemble({
    required List<ParsedVplLine> textLines,
    required List<VplSqlVerseMetadata> metadata,
  }) {
    final metadataByStart = <_VerseAddress, VplSqlVerseMetadata>{};
    for (final item in metadata) {
      final key = (
        bookCode: item.bookCode,
        chapter: item.chapter,
        verse: item.startVerse,
      );
      if (metadataByStart[key] != null) {
        throw const VerseAssemblyException('Duplicate SQL start address');
      }
      metadataByStart[key] = item;
    }

    final usedMetadata = <VplSqlVerseMetadata>{};
    final seenText = <_VerseAddress>{};
    final seenSlots = <_VerseAddress>{};
    final units = <ParsedVerseUnit>[];
    final slots = <ParsedVerseSlot>[];

    for (final line in textLines) {
      String bookCode;
      try {
        bookCode = BookCodeMap.normalizeText(line.bookCode);
      } on FormatException catch (error) {
        throw VerseAssemblyException(error.message);
      }
      final key = (
        bookCode: bookCode,
        chapter: line.chapter,
        verse: line.verse,
      );
      if (!seenText.add(key)) {
        throw const VerseAssemblyException('Duplicate VPL text address');
      }

      final item = metadataByStart[key];
      if (line.status == SourceTextStatus.present && item == null) {
        throw const VerseAssemblyException(
          'Present VPL text has no SQL metadata',
        );
      }
      if (item != null) {
        usedMetadata.add(item);
      }

      final endVerse = item?.endVerse ?? line.verse;
      final unitOrdinal = units.length;
      units.add(
        ParsedVerseUnit(
          sourceOrder: unitOrdinal,
          sourceVerseId: item?.sourceVerseId,
          bookCode: bookCode,
          chapter: line.chapter,
          startVerse: line.verse,
          endVerse: endVerse,
          text: line.text,
          status: line.status,
        ),
      );
      for (var verse = line.verse; verse <= endVerse; verse++) {
        final slotKey = (
          bookCode: bookCode,
          chapter: line.chapter,
          verse: verse,
        );
        if (!seenSlots.add(slotKey)) {
          throw const VerseAssemblyException('Overlapping verse slot');
        }
        slots.add(
          ParsedVerseSlot(
            bookCode: bookCode,
            chapter: line.chapter,
            verse: verse,
            unitOrdinal: unitOrdinal,
          ),
        );
      }
    }

    if (usedMetadata.length != metadata.length) {
      throw const VerseAssemblyException('SQL metadata has no VPL text');
    }
    return VerseAssemblyResult(units: units, slots: slots);
  }
}

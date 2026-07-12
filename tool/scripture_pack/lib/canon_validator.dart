import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';

import 'verse_unit_assembler.dart';

final class CanonBook {
  const CanonBook({required this.code, required this.chapterCount});

  final String code;
  final int chapterCount;
}

final class CanonDefinition {
  CanonDefinition({required this.canonId, required List<CanonBook> books})
    : books = List.unmodifiable(books) {
    if (canonId.isEmpty || this.books.isEmpty) {
      throw const FormatException('Canon metadata must not be empty');
    }
    final seen = <String>{};
    for (final book in this.books) {
      if (!_bookCode.hasMatch(book.code) ||
          book.chapterCount <= 0 ||
          !seen.add(book.code)) {
        throw const FormatException('Canon book metadata is invalid');
      }
    }
    if (canonId == 'protestant66') {
      final expected = protestant66BookOrder.keys.toList(growable: false);
      final actual = this.books
          .map((book) => book.code)
          .toList(growable: false);
      if (actual.length != expected.length || !_sameValues(actual, expected)) {
        throw const FormatException('Protestant canon order is invalid');
      }
    }
  }

  final String canonId;
  final List<CanonBook> books;

  static Future<CanonDefinition> load(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Canon root must be an object');
    }
    final canonId = decoded['canonId'];
    final rawBooks = decoded['books'];
    if (canonId is! String || rawBooks is! List<Object?>) {
      throw const FormatException('Canon fields are invalid');
    }
    final books = rawBooks
        .map((rawBook) {
          if (rawBook is! List<Object?> ||
              rawBook.length != 2 ||
              rawBook[0] is! String ||
              rawBook[1] is! int) {
            throw const FormatException('Canon book row is invalid');
          }
          return CanonBook(
            code: rawBook[0]! as String,
            chapterCount: rawBook[1]! as int,
          );
        })
        .toList(growable: false);
    return CanonDefinition(canonId: canonId, books: books);
  }

  static final _bookCode = RegExp(r'^[1-4A-Z][A-Z0-9]{2}$');
}

final class CanonValidationResult {
  CanonValidationResult({
    required List<ParsedVerseUnit> units,
    required List<ParsedVerseSlot> slots,
  }) : units = List.unmodifiable(units),
       slots = List.unmodifiable(slots);

  final List<ParsedVerseUnit> units;
  final List<ParsedVerseSlot> slots;

  int get bridgeUnitCount {
    return units.where((unit) => unit.endVerse > unit.startVerse).length;
  }

  int get extraBridgeSlotCount {
    return units.fold(0, (sum, unit) => sum + unit.endVerse - unit.startVerse);
  }

  int get omittedSlotCount {
    final omittedOrdinals = units
        .where((unit) => unit.status == SourceTextStatus.omitted)
        .map((unit) => unit.sourceOrder)
        .toSet();
    return slots
        .where((slot) => omittedOrdinals.contains(slot.unitOrdinal))
        .length;
  }
}

final class CanonValidationException implements Exception {
  const CanonValidationException(this.message);

  final String message;

  @override
  String toString() => 'CanonValidationException: $message';
}

final class CanonValidator {
  CanonValidationResult validate({
    required CanonDefinition canon,
    required List<ParsedVerseUnit> units,
    required List<ParsedVerseSlot> slots,
    required bool filterNonCanon,
  }) {
    final canonByCode = <String, CanonBook>{
      for (final book in canon.books) book.code: book,
    };
    final oldOrdinals = <int>{};
    for (final unit in units) {
      if (!oldOrdinals.add(unit.sourceOrder)) {
        throw const CanonValidationException('Duplicate source order');
      }
    }

    final remappedOrdinals = <int, int>{};
    final filteredUnits = <ParsedVerseUnit>[];
    for (final unit in units) {
      if (!canonByCode.containsKey(unit.bookCode)) {
        if (filterNonCanon) {
          continue;
        }
        throw CanonValidationException('Book outside canon: ${unit.bookCode}');
      }
      final newOrdinal = filteredUnits.length;
      remappedOrdinals[unit.sourceOrder] = newOrdinal;
      filteredUnits.add(
        ParsedVerseUnit(
          sourceOrder: newOrdinal,
          sourceVerseId: unit.sourceVerseId,
          bookCode: unit.bookCode,
          chapter: unit.chapter,
          startVerse: unit.startVerse,
          endVerse: unit.endVerse,
          text: unit.text,
          status: unit.status,
        ),
      );
    }

    final filteredSlots = <ParsedVerseSlot>[];
    for (final slot in slots) {
      if (!canonByCode.containsKey(slot.bookCode)) {
        if (filterNonCanon) {
          continue;
        }
        throw CanonValidationException('Slot outside canon: ${slot.bookCode}');
      }
      final newOrdinal = remappedOrdinals[slot.unitOrdinal];
      if (newOrdinal == null) {
        throw const CanonValidationException(
          'Slot references a missing text unit',
        );
      }
      filteredSlots.add(
        ParsedVerseSlot(
          bookCode: slot.bookCode,
          chapter: slot.chapter,
          verse: slot.verse,
          unitOrdinal: newOrdinal,
        ),
      );
    }

    _validateCanonicalData(canon, filteredUnits, filteredSlots);
    return CanonValidationResult(units: filteredUnits, slots: filteredSlots);
  }

  void _validateCanonicalData(
    CanonDefinition canon,
    List<ParsedVerseUnit> units,
    List<ParsedVerseSlot> slots,
  ) {
    final bookOrdinals = <String, int>{
      for (var index = 0; index < canon.books.length; index++)
        canon.books[index].code: index,
    };
    final chapters = <({String book, int chapter})>{};
    var previousSortKey = -1;
    for (final unit in units) {
      final bookOrdinal = bookOrdinals[unit.bookCode]!;
      final book = canon.books[bookOrdinal];
      if (unit.chapter <= 0 ||
          unit.chapter > book.chapterCount ||
          unit.startVerse <= 0 ||
          unit.endVerse < unit.startVerse) {
        throw const CanonValidationException('Invalid text unit range');
      }
      final sortKey =
          bookOrdinal * 100000000 + unit.chapter * 100000 + unit.startVerse;
      if (sortKey <= previousSortKey) {
        throw const CanonValidationException(
          'Text units are not in canonical order',
        );
      }
      previousSortKey = sortKey;
    }

    final slotAddresses = <({String book, int chapter, int verse})>{};
    for (final slot in slots) {
      final bookOrdinal = bookOrdinals[slot.bookCode];
      if (bookOrdinal == null ||
          slot.chapter <= 0 ||
          slot.chapter > canon.books[bookOrdinal].chapterCount ||
          slot.verse <= 0 ||
          slot.unitOrdinal < 0 ||
          slot.unitOrdinal >= units.length) {
        throw const CanonValidationException('Invalid verse slot');
      }
      final address = (
        book: slot.bookCode,
        chapter: slot.chapter,
        verse: slot.verse,
      );
      if (!slotAddresses.add(address)) {
        throw const CanonValidationException('Duplicate verse slot');
      }
      final unit = units[slot.unitOrdinal];
      if (unit.bookCode != slot.bookCode ||
          unit.chapter != slot.chapter ||
          slot.verse < unit.startVerse ||
          slot.verse > unit.endVerse) {
        throw const CanonValidationException(
          'Slot is outside its text unit range',
        );
      }
      chapters.add((book: slot.bookCode, chapter: slot.chapter));
    }

    for (final unit in units) {
      for (var verse = unit.startVerse; verse <= unit.endVerse; verse++) {
        if (!slotAddresses.contains((
          book: unit.bookCode,
          chapter: unit.chapter,
          verse: verse,
        ))) {
          throw const CanonValidationException(
            'Text unit has a missing verse slot',
          );
        }
      }
    }
    for (final book in canon.books) {
      for (var chapter = 1; chapter <= book.chapterCount; chapter++) {
        if (!chapters.contains((book: book.code, chapter: chapter))) {
          throw CanonValidationException(
            'Missing chapter ${book.code} $chapter',
          );
        }
      }
    }
  }
}

bool _sameValues(List<String> left, List<String> right) {
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

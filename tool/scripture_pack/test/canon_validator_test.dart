import 'dart:io';

import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:test/test.dart';

// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/canon_validator.dart';
// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/verse_unit_assembler.dart';

void main() {
  test('loads the exact 66-book, 1189-chapter canon', () async {
    final canon = await CanonDefinition.load(
      File('assets/scripture/canon/protestant66.json'),
    );

    expect(canon.canonId, 'protestant66');
    expect(canon.books, hasLength(66));
    expect(
      canon.books.fold<int>(0, (sum, book) => sum + book.chapterCount),
      1189,
    );
    expect(canon.books.first.code, 'GEN');
    expect(canon.books.last.code, 'REV');
  });

  test('filters non-canon books and remaps unit ordinals', () {
    final result = CanonValidator().validate(
      canon: CanonDefinition(
        canonId: 'fixture',
        books: const [
          CanonBook(code: 'GEN', chapterCount: 1),
          CanonBook(code: 'JHN', chapterCount: 1),
        ],
      ),
      filterNonCanon: true,
      units: [unit(0, 'GEN', 1, 1), unit(1, 'TOB', 1, 1), unit(2, 'JHN', 1, 1)],
      slots: const [
        ParsedVerseSlot(bookCode: 'GEN', chapter: 1, verse: 1, unitOrdinal: 0),
        ParsedVerseSlot(bookCode: 'TOB', chapter: 1, verse: 1, unitOrdinal: 1),
        ParsedVerseSlot(bookCode: 'JHN', chapter: 1, verse: 1, unitOrdinal: 2),
      ],
    );

    expect(result.units.map((value) => value.bookCode), ['GEN', 'JHN']);
    expect(result.slots.map((value) => value.unitOrdinal), [0, 1]);
  });

  test('rejects a missing expected chapter', () {
    expect(
      () => CanonValidator().validate(
        canon: CanonDefinition(
          canonId: 'fixture',
          books: const [CanonBook(code: 'GEN', chapterCount: 2)],
        ),
        filterNonCanon: false,
        units: [unit(0, 'GEN', 1, 1)],
        slots: const [
          ParsedVerseSlot(
            bookCode: 'GEN',
            chapter: 1,
            verse: 1,
            unitOrdinal: 0,
          ),
        ],
      ),
      throwsA(isA<CanonValidationException>()),
    );
  });

  test('rejects duplicate slots and units outside their declared range', () {
    final units = [unit(0, 'GEN', 1, 1)];
    const slot = ParsedVerseSlot(
      bookCode: 'GEN',
      chapter: 1,
      verse: 1,
      unitOrdinal: 0,
    );
    expect(
      () => CanonValidator().validate(
        canon: CanonDefinition(
          canonId: 'fixture',
          books: const [CanonBook(code: 'GEN', chapterCount: 1)],
        ),
        filterNonCanon: false,
        units: units,
        slots: const [slot, slot],
      ),
      throwsA(isA<CanonValidationException>()),
    );
  });
}

ParsedVerseUnit unit(int sourceOrder, String book, int chapter, int verse) {
  return ParsedVerseUnit(
    sourceOrder: sourceOrder,
    sourceVerseId: '$book${chapter}_$verse',
    bookCode: book,
    chapter: chapter,
    startVerse: verse,
    endVerse: verse,
    text: 'text',
    status: SourceTextStatus.present,
  );
}

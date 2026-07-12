import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:test/test.dart';

// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/verse_unit_assembler.dart';
// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/vpl_parser.dart';
// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/vpl_sql_metadata_parser.dart';

void main() {
  test('assembles one SQL bridge into one unit and two slots', () {
    final result = VerseUnitAssembler().assemble(
      textLines: const [
        ParsedVplLine(
          bookCode: 'GEN',
          chapter: 24,
          verse: 29,
          text: '利百加有一个哥哥，名叫拉班。',
          status: SourceTextStatus.present,
        ),
      ],
      metadata: const [
        VplSqlVerseMetadata(
          sourceVerseId: 'GN24_29',
          bookCode: 'GEN',
          chapter: 24,
          startVerse: 29,
          endVerse: 30,
        ),
      ],
    );

    expect(result.units.single.startVerse, 29);
    expect(result.units.single.endVerse, 30);
    expect(result.slots.map((slot) => slot.verse), [29, 30]);
    expect(result.slots.map((slot) => slot.unitOrdinal), [0, 0]);
  });

  test('keeps a TXT-only omitted verse as one omitted slot', () {
    final result = VerseUnitAssembler().assemble(
      textLines: const [
        ParsedVplLine(
          bookCode: 'LUK',
          chapter: 17,
          verse: 36,
          text: '',
          status: SourceTextStatus.omitted,
        ),
      ],
      metadata: const [],
    );

    expect(result.units.single.status, SourceTextStatus.omitted);
    expect(result.slots.single.verse, 36);
  });

  test('rejects present text without metadata and orphan metadata', () {
    const text = ParsedVplLine(
      bookCode: 'GEN',
      chapter: 1,
      verse: 1,
      text: 'In the beginning.',
      status: SourceTextStatus.present,
    );
    const metadata = VplSqlVerseMetadata(
      sourceVerseId: 'GN1_1',
      bookCode: 'GEN',
      chapter: 1,
      startVerse: 1,
      endVerse: 1,
    );

    expect(
      () => VerseUnitAssembler().assemble(
        textLines: const [text],
        metadata: const [],
      ),
      throwsA(isA<VerseAssemblyException>()),
    );
    expect(
      () => VerseUnitAssembler().assemble(
        textLines: const [],
        metadata: const [metadata],
      ),
      throwsA(isA<VerseAssemblyException>()),
    );
  });

  test('rejects overlapping slot ranges', () {
    expect(
      () => VerseUnitAssembler().assemble(
        textLines: const [
          ParsedVplLine(
            bookCode: 'GEN',
            chapter: 1,
            verse: 1,
            text: 'one',
            status: SourceTextStatus.present,
          ),
          ParsedVplLine(
            bookCode: 'GEN',
            chapter: 1,
            verse: 2,
            text: 'two',
            status: SourceTextStatus.present,
          ),
        ],
        metadata: const [
          VplSqlVerseMetadata(
            sourceVerseId: 'GN1_1',
            bookCode: 'GEN',
            chapter: 1,
            startVerse: 1,
            endVerse: 2,
          ),
          VplSqlVerseMetadata(
            sourceVerseId: 'GN1_2',
            bookCode: 'GEN',
            chapter: 1,
            startVerse: 2,
            endVerse: 2,
          ),
        ],
      ),
      throwsA(isA<VerseAssemblyException>()),
    );
  });
}

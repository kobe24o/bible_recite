import 'package:test/test.dart';

// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/book_code_map.dart';
// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/vpl_sql_metadata_parser.dart';

void main() {
  test('parses a bridge from one restricted INSERT row', () async {
    final rows = await VplSqlMetadataParser(expectedTableName: 'fixture_vpl')
        .parse(
          Stream.value(
            'INSERT INTO fixture_vpl VALUES '
            '("GN24_29","002_24_29","GEN","24","29","30","text ");',
          ),
        )
        .toList();

    expect(
      rows.single,
      const VplSqlVerseMetadata(
        sourceVerseId: 'GN24_29',
        bookCode: 'GEN',
        chapter: 24,
        startVerse: 29,
        endVerse: 30,
      ),
    );
  });

  test('rejects DDL, comments, and trailing executable text', () async {
    for (final line in [
      'DROP TABLE fixture_vpl;',
      '-- INSERT INTO fixture_vpl VALUES ("x");',
      'INSERT INTO fixture_vpl VALUES '
          '("GN1_1","002_1_1","GEN","1","1","1","text "); DROP TABLE x;',
    ]) {
      await expectLater(
        VplSqlMetadataParser(
          expectedTableName: 'fixture_vpl',
        ).parse(Stream.value(line)).toList(),
        throwsA(isA<VplSqlFormatException>()),
      );
    }
  });

  test('rejects duplicate IDs and reversed bridge ranges', () async {
    const valid =
        'INSERT INTO fixture_vpl VALUES '
        '("GN1_1","002_1_1","GEN","1","1","1","text ");';
    await expectLater(
      VplSqlMetadataParser(
        expectedTableName: 'fixture_vpl',
      ).parse(Stream.fromIterable([valid, valid])).toList(),
      throwsA(isA<VplSqlFormatException>()),
    );
    await expectLater(
      VplSqlMetadataParser(expectedTableName: 'fixture_vpl')
          .parse(
            Stream.value(
              'INSERT INTO fixture_vpl VALUES '
              '("GN1_2","002_1_2","GEN","1","2","1","text ");',
            ),
          )
          .toList(),
      throwsA(isA<VplSqlFormatException>()),
    );
  });

  test('normalizes distinct TXT and SQL book abbreviations', () {
    expect(BookCodeMap.normalizeText('SOL'), 'SNG');
    expect(BookCodeMap.normalizeText('JOH'), 'JHN');
    expect(BookCodeMap.normalizeSql('SNG'), 'SNG');
    expect(BookCodeMap.normalizeSql('JHN'), 'JHN');
    expect(BookCodeMap.normalizeText('4ES'), '4ES');
    expect(BookCodeMap.normalizeSql('2ES'), '4ES');
    expect(() => BookCodeMap.normalizeSql('BAD'), throwsFormatException);
  });
}

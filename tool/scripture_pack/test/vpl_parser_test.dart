import 'package:bible_recite/src/features/scripture/domain/scripture_models.dart';
import 'package:test/test.dart';

// This build tool is intentionally self-contained under tool/scripture_pack.
// ignore: avoid_relative_lib_imports
import '../lib/vpl_parser.dart';

void main() {
  test('parses BOM, blank lines, and exact source text', () async {
    final lines = Stream.fromIterable([
      '\uFEFFGEN 1:1 起初，　神创造天地。',
      '',
      'JHN 3:16 神爱世人。',
    ]);

    final verses = await VplParser().parse(lines).toList();

    expect(verses.first.bookCode, 'GEN');
    expect(verses.first.text, '起初，　神创造天地。');
    expect(
      verses.last,
      const ParsedVplLine(
        bookCode: 'JHN',
        chapter: 3,
        verse: 16,
        text: '神爱世人。',
        status: SourceTextStatus.present,
      ),
    );
  });

  test('keeps an explicit empty WEB verse as omitted', () async {
    final verses = await VplParser().parse(Stream.value('LUK 17:36 ')).toList();

    expect(verses.single.status, SourceTextStatus.omitted);
    expect(verses.single.text, '');
  });

  test('rejects malformed or nonpositive non-empty lines', () async {
    await expectLater(
      VplParser().parse(Stream.value('GEN one:1 invalid')).toList(),
      throwsA(isA<VplFormatException>()),
    );
    await expectLater(
      VplParser().parse(Stream.value('GEN 0:1 invalid')).toList(),
      throwsA(isA<VplFormatException>()),
    );
  });
}

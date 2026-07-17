import 'dart:io';

import 'package:test/test.dart';

import '../lib/markdown_plan_parser.dart';

String fixture(String name) =>
    File('tool/cloud_plan/test/fixtures/$name').readAsStringSync();

void main() {
  const parser = MarkdownPlanParser();

  test('classic parser keeps full chapters and partial verse ranges', () {
    final passages = parser.parseClassic(fixture('classic_headings.md'));

    expect(passages, hasLength(3));
    expect(passages[0].bookId, 'PSA');
    expect(passages[0].startVerse, isNull);
    expect(passages[0].endVerse, isNull);
    expect(passages[1].bookId, 'LUK');
    expect(passages[1].startChapter, 1);
    expect(passages[1].endChapter, 1);
    expect(passages[1].startVerse, 46);
    expect(passages[1].endVerse, 56);
    expect(passages[2].order, 3);
  });

  test('key verse parser preserves a multi-verse ending', () {
    final passages = parser.parseKeyVerses(fixture('key_verses.md'));

    expect(passages, hasLength(2));
    expect(passages[0].bookId, 'GEN');
    expect(passages[0].startVerse, 1);
    expect(passages[0].endVerse, 1);
    expect(passages[1].bookId, 'NUM');
    expect(passages[1].startChapter, 14);
    expect(passages[1].startVerse, 22);
    expect(passages[1].endVerse, 23);
  });

  test('parser rejects an unknown Chinese book name', () {
    expect(
      () => parser.parseClassic('## 1. 示例：《不存在书》第 1 篇 (全篇)'),
      throwsFormatException,
    );
  });
}

// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:test/test.dart';

import '../lib/cloud_plan_models.dart';
import '../lib/feishu_csv_generator.dart';

void main() {
  test('catalog uses the minimum supported maximum verse', () {
    const entry = ChapterCatalogEntry(
      bookId: 'PSA',
      canonOrder: 19,
      chapter: 1,
      simplifiedMaxVerse: 6,
      traditionalMaxVerse: 7,
      englishMaxVerse: 8,
    );

    expect(entry.publishMaxVerse, 6);
  });

  test('validator rejects a verse beyond the selected chapter', () {
    const entry = ChapterCatalogEntry(
      bookId: 'PSA',
      canonOrder: 19,
      chapter: 1,
      simplifiedMaxVerse: 6,
      traditionalMaxVerse: 6,
      englishMaxVerse: 6,
    );
    final catalog = {('PSA', 1): entry};

    expect(
      () => expandAndValidate(
        const CloudPassageRef(
          order: 1,
          bookId: 'PSA',
          startChapter: 1,
          endChapter: 1,
          startVerse: 1,
          endVerse: 7,
        ),
        catalog,
      ),
      throwsFormatException,
    );
  });

  test('catalog loads all 1189 Protestant chapters from all three packs', () {
    final catalog = loadChapterCatalog();

    expect(catalog, hasLength(1189));
    expect(catalog[('GEN', 1)]?.canonOrder, 1);
    expect(catalog[('REV', 22)]?.canonOrder, 66);
    expect(catalog[('PSA', 23)]?.publishMaxVerse, 6);
  });

  test('generator writes deterministic UTF-8 BOM CSV contracts', () {
    final output = Directory.systemTemp.createTempSync('feishu-cloud-plan-');
    addTearDown(() => output.deleteSync(recursive: true));

    final summary = const FeishuTemplateGenerator().generate(
      TemplateGenerationRequest(
        classicMarkdownPath:
            'tool/cloud_plan/test/fixtures/classic_headings.md',
        keyVersesMarkdownPath: 'tool/cloud_plan/test/fixtures/key_verses.md',
        outputDirectoryPath: output.path,
        expectedClassicCount: 3,
        expectedKeyVerseCount: 2,
      ),
    );

    expect(summary.chapterCount, 1189);
    expect(summary.planCount, 2);
    expect(summary.passageCount, 5);
    final chapterBytes = File('${output.path}/章节目录.csv').readAsBytesSync();
    expect(chapterBytes.take(3), [0xEF, 0xBB, 0xBF]);
    final planCsv = File('${output.path}/背诵计划.csv').readAsStringSync();
    expect(planCsv, contains('计划 ID,计划名称,计划简介,是否推送,修订号,默认译本'));
    final passageCsv = File('${output.path}/计划经文.csv').readAsStringSync();
    expect(passageCsv, contains('key-verses-66-002,key-verses-66,2'));
    expect(passageCsv, contains(',NUM.014｜民数记 14,22,NUM.014｜民数记 14,23'));
  });
}

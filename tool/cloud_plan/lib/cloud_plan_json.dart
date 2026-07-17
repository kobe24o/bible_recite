import 'dart:convert';
import 'dart:io';

import 'cloud_plan_models.dart';
import 'feishu_csv_generator.dart';
import 'markdown_plan_parser.dart';

final class CloudPlanJsonRequest {
  const CloudPlanJsonRequest({
    required this.classicMarkdownPath,
    required this.keyVersesMarkdownPath,
    required this.outputPath,
    this.scriptureAssetsPath = 'assets/scripture',
  });

  final String classicMarkdownPath;
  final String keyVersesMarkdownPath;
  final String outputPath;
  final String scriptureAssetsPath;
}

final class CloudPlanJsonSummary {
  const CloudPlanJsonSummary({
    required this.classicPassageCount,
    required this.keyVersePassageCount,
  });

  final int classicPassageCount;
  final int keyVersePassageCount;
}

final class CloudPlanJsonGenerator {
  const CloudPlanJsonGenerator();

  CloudPlanJsonSummary generate(
    CloudPlanJsonRequest request, {
    File? outputFile,
  }) {
    const parser = MarkdownPlanParser();
    final catalog = loadChapterCatalog(
      scriptureAssetsPath: request.scriptureAssetsPath,
    );
    final classic = parser
        .parseClassic(File(request.classicMarkdownPath).readAsStringSync())
        .map((item) => expandAndValidate(item, catalog))
        .toList(growable: false);
    final keyVerses = parser
        .parseKeyVerses(File(request.keyVersesMarkdownPath).readAsStringSync())
        .map((item) => expandAndValidate(item, catalog))
        .toList(growable: false);
    if (classic.length != 20 || keyVerses.length != 66) {
      throw FormatException(
        'Expected 20 classic passages and 66 key verses, found '
        '${classic.length} and ${keyVerses.length}',
      );
    }

    final manifest = <String, Object?>{
      'protocolVersion': 1,
      'publisher': '背诵助手官方',
      'plans': [
        _plan(
          id: 'classic-passages',
          title: '圣经经典篇章',
          description: '20 段跨卷经典经文背诵计划',
          tag: '经典篇章',
          passages: classic,
        ),
        _plan(
          id: 'key-verses-66',
          title: '每卷书钥节',
          description: '66 卷圣经每卷一处钥节背诵计划',
          tag: '每卷钥节',
          passages: keyVerses,
        ),
      ],
    };
    final target = outputFile ?? File(request.outputPath);
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      flush: true,
    );
    return CloudPlanJsonSummary(
      classicPassageCount: classic.length,
      keyVersePassageCount: keyVerses.length,
    );
  }
}

Map<String, Object?> _plan({
  required String id,
  required String title,
  required String description,
  required String tag,
  required List<CloudPassageRef> passages,
}) => <String, Object?>{
  'id': id,
  'title': title,
  'description': description,
  'push': true,
  'revision': 1,
  'defaultTranslationId': 'cmn-cu89s',
  'defaultStartDate': null,
  'defaultEndDate': null,
  'sourceName': '背诵助手官方',
  'tag': tag,
  'passages': [
    for (final passage in passages)
      <String, Object?>{
        'order': passage.order,
        'bookId': passage.bookId,
        'startChapter': passage.startChapter,
        'startVerse': passage.startVerse,
        'endChapter': passage.endChapter,
        'endVerse': passage.endVerse,
      },
  ],
};

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import 'cloud_plan_models.dart';
import 'markdown_plan_parser.dart';

typedef ChapterKey = (String, int);

final class ChapterCatalogEntry {
  const ChapterCatalogEntry({
    required this.bookId,
    required this.canonOrder,
    required this.chapter,
    required this.simplifiedMaxVerse,
    required this.traditionalMaxVerse,
    required this.englishMaxVerse,
  });

  final String bookId;
  final int canonOrder;
  final int chapter;
  final int simplifiedMaxVerse;
  final int traditionalMaxVerse;
  final int englishMaxVerse;

  int get publishMaxVerse => math.min(
    simplifiedMaxVerse,
    math.min(traditionalMaxVerse, englishMaxVerse),
  );

  BookMetadata get book => bookMetadataById[bookId]!;

  String get displayKey =>
      '$bookId.${chapter.toString().padLeft(3, '0')}｜${book.simplifiedName} $chapter';
}

final class TemplateGenerationRequest {
  const TemplateGenerationRequest({
    required this.classicMarkdownPath,
    required this.keyVersesMarkdownPath,
    required this.outputDirectoryPath,
    this.scriptureAssetsPath = 'assets/scripture',
    this.expectedClassicCount = 20,
    this.expectedKeyVerseCount = 66,
  });

  final String classicMarkdownPath;
  final String keyVersesMarkdownPath;
  final String outputDirectoryPath;
  final String scriptureAssetsPath;
  final int expectedClassicCount;
  final int expectedKeyVerseCount;
}

final class TemplateGenerationSummary {
  const TemplateGenerationSummary({
    required this.chapterCount,
    required this.planCount,
    required this.passageCount,
    required this.classicPassageCount,
    required this.keyVersePassageCount,
  });

  final int chapterCount;
  final int planCount;
  final int passageCount;
  final int classicPassageCount;
  final int keyVersePassageCount;
}

Map<ChapterKey, ChapterCatalogEntry> loadChapterCatalog({
  String scriptureAssetsPath = 'assets/scripture',
}) {
  final simplified = _readPack(
    '$scriptureAssetsPath/cmn-cu89s/scripture.sqlite',
  );
  final traditional = _readPack(
    '$scriptureAssetsPath/cmn-cu89t/scripture.sqlite',
  );
  final english = _readPack('$scriptureAssetsPath/eng-web/scripture.sqlite');
  if (!_sameKeys(simplified, traditional) || !_sameKeys(simplified, english)) {
    throw const FormatException(
      'The three scripture packs do not expose identical chapter keys',
    );
  }

  final catalog = <ChapterKey, ChapterCatalogEntry>{};
  for (final key in simplified.keys) {
    final simplifiedChapter = simplified[key]!;
    final traditionalChapter = traditional[key]!;
    final englishChapter = english[key]!;
    if (simplifiedChapter.canonOrder != traditionalChapter.canonOrder ||
        simplifiedChapter.canonOrder != englishChapter.canonOrder) {
      throw FormatException('Canon order differs for ${key.$1} ${key.$2}');
    }
    if (!bookMetadataById.containsKey(key.$1)) {
      throw FormatException('Missing book metadata for ${key.$1}');
    }
    catalog[key] = ChapterCatalogEntry(
      bookId: key.$1,
      canonOrder: simplifiedChapter.canonOrder,
      chapter: key.$2,
      simplifiedMaxVerse: simplifiedChapter.maxVerse,
      traditionalMaxVerse: traditionalChapter.maxVerse,
      englishMaxVerse: englishChapter.maxVerse,
    );
  }
  return Map.unmodifiable(catalog);
}

CloudPassageRef expandAndValidate(
  CloudPassageRef input,
  Map<ChapterKey, ChapterCatalogEntry> catalog,
) {
  final start = catalog[(input.bookId, input.startChapter)];
  final end = catalog[(input.bookId, input.endChapter)];
  if (start == null || end == null) {
    throw const FormatException('Unknown chapter');
  }
  final startVerse = input.startVerse ?? 1;
  final endVerse = input.endVerse ?? end.publishMaxVerse;
  if (startVerse < 1 || startVerse > start.publishMaxVerse) {
    throw const FormatException('Start verse is outside the selected chapter');
  }
  if (endVerse < 1 || endVerse > end.publishMaxVerse) {
    throw const FormatException('End verse is outside the selected chapter');
  }
  if (input.startChapter > input.endChapter ||
      (input.startChapter == input.endChapter && startVerse > endVerse)) {
    throw const FormatException('Passage range is reversed');
  }
  return CloudPassageRef(
    order: input.order,
    bookId: input.bookId,
    startChapter: input.startChapter,
    endChapter: input.endChapter,
    startVerse: startVerse,
    endVerse: endVerse,
  );
}

final class FeishuTemplateGenerator {
  const FeishuTemplateGenerator();

  TemplateGenerationSummary generate(TemplateGenerationRequest request) {
    const parser = MarkdownPlanParser();
    final classic = parser.parseClassic(
      File(request.classicMarkdownPath).readAsStringSync(),
    );
    final keyVerses = parser.parseKeyVerses(
      File(request.keyVersesMarkdownPath).readAsStringSync(),
    );
    if (classic.length != request.expectedClassicCount) {
      throw FormatException(
        'Expected ${request.expectedClassicCount} classic passages, '
        'found ${classic.length}',
      );
    }
    if (keyVerses.length != request.expectedKeyVerseCount) {
      throw FormatException(
        'Expected ${request.expectedKeyVerseCount} key verses, '
        'found ${keyVerses.length}',
      );
    }

    final catalog = loadChapterCatalog(
      scriptureAssetsPath: request.scriptureAssetsPath,
    );
    final expandedClassic = classic
        .map((passage) => expandAndValidate(passage, catalog))
        .toList(growable: false);
    final expandedKeyVerses = keyVerses
        .map((passage) => expandAndValidate(passage, catalog))
        .toList(growable: false);

    final output = Directory(request.outputDirectoryPath)
      ..createSync(recursive: true);
    _writeCsv(File('${output.path}/章节目录.csv'), _chapterRows(catalog.values));
    _writeCsv(File('${output.path}/背诵计划.csv'), _planRows());
    _writeCsv(
      File('${output.path}/计划经文.csv'),
      _passageRows(
        'classic-passages',
        expandedClassic,
        catalog,
      ).followedBy(_passageRows('key-verses-66', expandedKeyVerses, catalog)),
    );

    return TemplateGenerationSummary(
      chapterCount: catalog.length,
      planCount: 2,
      passageCount: expandedClassic.length + expandedKeyVerses.length,
      classicPassageCount: expandedClassic.length,
      keyVersePassageCount: expandedKeyVerses.length,
    );
  }
}

Iterable<List<Object?>> _chapterRows(
  Iterable<ChapterCatalogEntry> entries,
) sync* {
  yield const [
    '章节键',
    '经卷 OSIS',
    '简体卷名',
    '繁体卷名',
    '英文卷名',
    '章号',
    '简体最大节数',
    '繁体最大节数',
    '英文最大节数',
    '发布最大节数',
    '正典顺序',
  ];
  final sorted = entries.toList()
    ..sort((a, b) {
      final byBook = a.canonOrder.compareTo(b.canonOrder);
      return byBook == 0 ? a.chapter.compareTo(b.chapter) : byBook;
    });
  for (final entry in sorted) {
    yield [
      entry.displayKey,
      entry.bookId,
      entry.book.simplifiedName,
      entry.book.traditionalName,
      entry.book.englishName,
      entry.chapter,
      entry.simplifiedMaxVerse,
      entry.traditionalMaxVerse,
      entry.englishMaxVerse,
      entry.publishMaxVerse,
      entry.canonOrder,
    ];
  }
}

Iterable<List<Object?>> _planRows() sync* {
  yield const [
    '计划 ID',
    '计划名称',
    '计划简介',
    '是否推送',
    '修订号',
    '默认译本',
    '默认开始日期',
    '默认结束日期',
    '来源名称',
    '协议版本',
    '标签',
  ];
  yield const [
    'classic-passages',
    '圣经经典篇章',
    '20 段跨卷经典经文背诵计划',
    '是',
    1,
    '简体',
    '',
    '',
    '背诵助手官方',
    '1',
    '经典篇章',
  ];
  yield const [
    'key-verses-66',
    '每卷书钥节',
    '66 卷圣经每卷一处钥节背诵计划',
    '是',
    1,
    '简体',
    '',
    '',
    '背诵助手官方',
    '1',
    '每卷钥节',
  ];
}

Iterable<List<Object?>> _passageRows(
  String planId,
  Iterable<CloudPassageRef> passages,
  Map<ChapterKey, ChapterCatalogEntry> catalog,
) sync* {
  if (planId == 'classic-passages') {
    yield const ['条目 ID', '所属计划', '经文顺序', '起始章节', '起始节', '终止章节', '终止节'];
  }
  for (final passage in passages) {
    final start = catalog[(passage.bookId, passage.startChapter)]!;
    final end = catalog[(passage.bookId, passage.endChapter)]!;
    yield [
      '$planId-${passage.order.toString().padLeft(3, '0')}',
      planId,
      passage.order,
      start.displayKey,
      passage.startVerse,
      end.displayKey,
      passage.endVerse,
    ];
  }
}

void _writeCsv(File file, Iterable<List<Object?>> rows) {
  final content = '${rows.map(_encodeCsvRow).join('\r\n')}\r\n';
  file.writeAsBytesSync(utf8.encode('\uFEFF$content'), flush: true);
}

String _encodeCsvRow(List<Object?> cells) => cells
    .map((cell) {
      final value = cell?.toString() ?? '';
      if (!value.contains(RegExp('[,"\\r\\n]'))) return value;
      return '"${value.replaceAll('"', '""')}"';
    })
    .join(',');

Map<ChapterKey, _PackChapter> _readPack(String path) {
  final database = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final rows = database.select('''
SELECT b.osis_id,
       b.ordinal,
       u.chapter,
       MAX(u.end_verse) AS max_verse
FROM books b
JOIN verse_unit u ON u.osis_book_id = b.osis_id
WHERE u.status = 'present'
GROUP BY b.osis_id, b.ordinal, b.chapter_count, u.chapter
ORDER BY b.ordinal, u.chapter
''');
    return {
      for (final row in rows)
        (row['osis_id'] as String, row['chapter'] as int): _PackChapter(
          canonOrder: row['ordinal'] as int,
          maxVerse: row['max_verse'] as int,
        ),
    };
  } finally {
    database.close();
  }
}

bool _sameKeys(Map<ChapterKey, Object?> a, Map<ChapterKey, Object?> b) =>
    a.length == b.length && a.keys.every(b.containsKey);

final class _PackChapter {
  const _PackChapter({required this.canonOrder, required this.maxVerse});

  final int canonOrder;
  final int maxVerse;
}

final class BookMetadata {
  const BookMetadata(
    this.id,
    this.simplifiedName,
    this.traditionalName,
    this.englishName,
  );

  final String id;
  final String simplifiedName;
  final String traditionalName;
  final String englishName;
}

const List<BookMetadata> bookMetadata = [
  BookMetadata('GEN', '创世记', '創世記', 'Genesis'),
  BookMetadata('EXO', '出埃及记', '出埃及記', 'Exodus'),
  BookMetadata('LEV', '利未记', '利未記', 'Leviticus'),
  BookMetadata('NUM', '民数记', '民數記', 'Numbers'),
  BookMetadata('DEU', '申命记', '申命記', 'Deuteronomy'),
  BookMetadata('JOS', '约书亚记', '約書亞記', 'Joshua'),
  BookMetadata('JDG', '士师记', '士師記', 'Judges'),
  BookMetadata('RUT', '路得记', '路得記', 'Ruth'),
  BookMetadata('1SA', '撒母耳记上', '撒母耳記上', '1 Samuel'),
  BookMetadata('2SA', '撒母耳记下', '撒母耳記下', '2 Samuel'),
  BookMetadata('1KI', '列王纪上', '列王紀上', '1 Kings'),
  BookMetadata('2KI', '列王纪下', '列王紀下', '2 Kings'),
  BookMetadata('1CH', '历代志上', '歷代志上', '1 Chronicles'),
  BookMetadata('2CH', '历代志下', '歷代志下', '2 Chronicles'),
  BookMetadata('EZR', '以斯拉记', '以斯拉記', 'Ezra'),
  BookMetadata('NEH', '尼希米记', '尼希米記', 'Nehemiah'),
  BookMetadata('EST', '以斯帖记', '以斯帖記', 'Esther'),
  BookMetadata('JOB', '约伯记', '約伯記', 'Job'),
  BookMetadata('PSA', '诗篇', '詩篇', 'Psalms'),
  BookMetadata('PRO', '箴言', '箴言', 'Proverbs'),
  BookMetadata('ECC', '传道书', '傳道書', 'Ecclesiastes'),
  BookMetadata('SNG', '雅歌', '雅歌', 'Song of Songs'),
  BookMetadata('ISA', '以赛亚书', '以賽亞書', 'Isaiah'),
  BookMetadata('JER', '耶利米书', '耶利米書', 'Jeremiah'),
  BookMetadata('LAM', '耶利米哀歌', '耶利米哀歌', 'Lamentations'),
  BookMetadata('EZK', '以西结书', '以西結書', 'Ezekiel'),
  BookMetadata('DAN', '但以理书', '但以理書', 'Daniel'),
  BookMetadata('HOS', '何西阿书', '何西阿書', 'Hosea'),
  BookMetadata('JOL', '约珥书', '約珥書', 'Joel'),
  BookMetadata('AMO', '阿摩司书', '阿摩司書', 'Amos'),
  BookMetadata('OBA', '俄巴底亚书', '俄巴底亞書', 'Obadiah'),
  BookMetadata('JON', '约拿书', '約拿書', 'Jonah'),
  BookMetadata('MIC', '弥迦书', '彌迦書', 'Micah'),
  BookMetadata('NAM', '那鸿书', '那鴻書', 'Nahum'),
  BookMetadata('HAB', '哈巴谷书', '哈巴谷書', 'Habakkuk'),
  BookMetadata('ZEP', '西番雅书', '西番雅書', 'Zephaniah'),
  BookMetadata('HAG', '哈该书', '哈該書', 'Haggai'),
  BookMetadata('ZEC', '撒迦利亚书', '撒迦利亞書', 'Zechariah'),
  BookMetadata('MAL', '玛拉基书', '瑪拉基書', 'Malachi'),
  BookMetadata('MAT', '马太福音', '馬太福音', 'Matthew'),
  BookMetadata('MRK', '马可福音', '馬可福音', 'Mark'),
  BookMetadata('LUK', '路加福音', '路加福音', 'Luke'),
  BookMetadata('JHN', '约翰福音', '約翰福音', 'John'),
  BookMetadata('ACT', '使徒行传', '使徒行傳', 'Acts'),
  BookMetadata('ROM', '罗马书', '羅馬書', 'Romans'),
  BookMetadata('1CO', '哥林多前书', '哥林多前書', '1 Corinthians'),
  BookMetadata('2CO', '哥林多后书', '哥林多後書', '2 Corinthians'),
  BookMetadata('GAL', '加拉太书', '加拉太書', 'Galatians'),
  BookMetadata('EPH', '以弗所书', '以弗所書', 'Ephesians'),
  BookMetadata('PHP', '腓立比书', '腓立比書', 'Philippians'),
  BookMetadata('COL', '歌罗西书', '歌羅西書', 'Colossians'),
  BookMetadata('1TH', '帖撒罗尼迦前书', '帖撒羅尼迦前書', '1 Thessalonians'),
  BookMetadata('2TH', '帖撒罗尼迦后书', '帖撒羅尼迦後書', '2 Thessalonians'),
  BookMetadata('1TI', '提摩太前书', '提摩太前書', '1 Timothy'),
  BookMetadata('2TI', '提摩太后书', '提摩太後書', '2 Timothy'),
  BookMetadata('TIT', '提多书', '提多書', 'Titus'),
  BookMetadata('PHM', '腓利门书', '腓利門書', 'Philemon'),
  BookMetadata('HEB', '希伯来书', '希伯來書', 'Hebrews'),
  BookMetadata('JAS', '雅各书', '雅各書', 'James'),
  BookMetadata('1PE', '彼得前书', '彼得前書', '1 Peter'),
  BookMetadata('2PE', '彼得后书', '彼得後書', '2 Peter'),
  BookMetadata('1JN', '约翰一书', '約翰一書', '1 John'),
  BookMetadata('2JN', '约翰二书', '約翰二書', '2 John'),
  BookMetadata('3JN', '约翰三书', '約翰三書', '3 John'),
  BookMetadata('JUD', '犹大书', '猶大書', 'Jude'),
  BookMetadata('REV', '启示录', '啟示錄', 'Revelation'),
];

final Map<String, BookMetadata> bookMetadataById = Map.unmodifiable({
  for (final book in bookMetadata) book.id: book,
});

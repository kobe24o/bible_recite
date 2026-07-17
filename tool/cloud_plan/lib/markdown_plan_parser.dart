import 'cloud_plan_models.dart';

final class MarkdownPlanParser {
  const MarkdownPlanParser();

  static final RegExp _classicHeading = RegExp(
    r'^##\s+(\d+)\.\s+.+?：《([^》]+)》第\s*(\d+)\s*[篇章](?:\s+(\d+)\s*[-–—]\s*(\d+)\s*节)?(?:\s|$)',
  );
  static final RegExp _keyHeading = RegExp(r'^###\s+\d+\.\s+《([^》]+)》');

  List<CloudPassageRef> parseClassic(String markdown) {
    final passages = <CloudPassageRef>[];
    for (final line in markdown.split(RegExp(r'\r?\n'))) {
      if (!line.startsWith(RegExp(r'##\s+\d+\.'))) continue;
      final match = _classicHeading.firstMatch(line);
      if (match == null) {
        throw FormatException('Malformed classic-plan heading: $line');
      }
      final order = int.parse(match.group(1)!);
      if (order != passages.length + 1) {
        throw FormatException('Classic-plan order is not contiguous: $order');
      }
      final startVerse = _optionalInt(match.group(4));
      final endVerse = _optionalInt(match.group(5));
      if ((startVerse == null) != (endVerse == null)) {
        throw FormatException('Incomplete verse range: $line');
      }
      final chapter = int.parse(match.group(3)!);
      passages.add(
        CloudPassageRef(
          order: order,
          bookId: _bookId(match.group(2)!),
          startChapter: chapter,
          endChapter: chapter,
          startVerse: startVerse,
          endVerse: endVerse,
        ),
      );
    }
    if (passages.isEmpty) {
      throw const FormatException('No classic-plan headings found');
    }
    return List.unmodifiable(passages);
  }

  List<CloudPassageRef> parseKeyVerses(String markdown) {
    final passages = <CloudPassageRef>[];
    final seenBooks = <String>{};
    String? activeBookName;
    String? activeBookId;
    var activeBookHasReference = false;

    for (final line in markdown.split(RegExp(r'\r?\n'))) {
      final heading = _keyHeading.firstMatch(line);
      if (heading != null) {
        if (activeBookName != null && !activeBookHasReference) {
          throw FormatException('Missing key verse for $activeBookName');
        }
        activeBookName = heading.group(1)!;
        activeBookId = _bookId(activeBookName);
        if (!seenBooks.add(activeBookId)) {
          throw FormatException('Duplicate key-verse book: $activeBookName');
        }
        activeBookHasReference = false;
        continue;
      }
      if (activeBookName == null || activeBookHasReference) continue;
      if (!line.startsWith(activeBookName)) continue;

      final reference = RegExp(
        '^${RegExp.escape(activeBookName)}\\s*(\\d+):(\\d+)(?:\\s*[-–—]\\s*(\\d+))?(?:\\s|\$)',
      ).firstMatch(line);
      if (reference == null) {
        throw FormatException('Malformed key verse for $activeBookName: $line');
      }
      final chapter = int.parse(reference.group(1)!);
      final startVerse = int.parse(reference.group(2)!);
      final endVerse = _optionalInt(reference.group(3)) ?? startVerse;
      if (chapter < 1 || startVerse < 1 || endVerse < startVerse) {
        throw FormatException('Invalid key verse for $activeBookName: $line');
      }
      passages.add(
        CloudPassageRef(
          order: passages.length + 1,
          bookId: activeBookId!,
          startChapter: chapter,
          endChapter: chapter,
          startVerse: startVerse,
          endVerse: endVerse,
        ),
      );
      activeBookHasReference = true;
    }

    if (activeBookName != null && !activeBookHasReference) {
      throw FormatException('Missing key verse for $activeBookName');
    }
    if (passages.isEmpty) {
      throw const FormatException('No key-verse entries found');
    }
    return List.unmodifiable(passages);
  }

  static int? _optionalInt(String? value) =>
      value == null ? null : int.parse(value);

  static String _bookId(String chineseName) {
    final id = _chineseBookIds[chineseName];
    if (id == null) {
      throw FormatException('Unknown Chinese book name: $chineseName');
    }
    return id;
  }
}

const Map<String, String> _chineseBookIds = {
  '创世记': 'GEN',
  '出埃及记': 'EXO',
  '利未记': 'LEV',
  '民数记': 'NUM',
  '申命记': 'DEU',
  '约书亚记': 'JOS',
  '士师记': 'JDG',
  '路得记': 'RUT',
  '撒母耳记上': '1SA',
  '撒母耳记下': '2SA',
  '列王纪上': '1KI',
  '列王纪下': '2KI',
  '历代志上': '1CH',
  '历代志下': '2CH',
  '以斯拉记': 'EZR',
  '尼希米记': 'NEH',
  '以斯帖记': 'EST',
  '约伯记': 'JOB',
  '诗篇': 'PSA',
  '箴言': 'PRO',
  '传道书': 'ECC',
  '雅歌': 'SNG',
  '以赛亚书': 'ISA',
  '耶利米书': 'JER',
  '耶利米哀歌': 'LAM',
  '以西结书': 'EZK',
  '但以理书': 'DAN',
  '何西阿书': 'HOS',
  '约珥书': 'JOL',
  '阿摩司书': 'AMO',
  '俄巴底亚书': 'OBA',
  '约拿书': 'JON',
  '弥迦书': 'MIC',
  '那鸿书': 'NAM',
  '哈巴谷书': 'HAB',
  '西番雅书': 'ZEP',
  '哈该书': 'HAG',
  '撒迦利亚书': 'ZEC',
  '玛拉基书': 'MAL',
  '马太福音': 'MAT',
  '马可福音': 'MRK',
  '路加福音': 'LUK',
  '约翰福音': 'JHN',
  '使徒行传': 'ACT',
  '罗马书': 'ROM',
  '哥林多前书': '1CO',
  '哥林多后书': '2CO',
  '加拉太书': 'GAL',
  '以弗所书': 'EPH',
  '腓立比书': 'PHP',
  '歌罗西书': 'COL',
  '帖撒罗尼迦前书': '1TH',
  '帖撒罗尼迦后书': '2TH',
  '提摩太前书': '1TI',
  '提摩太后书': '2TI',
  '提多书': 'TIT',
  '腓利门书': 'PHM',
  '希伯来书': 'HEB',
  '雅各书': 'JAS',
  '彼得前书': '1PE',
  '彼得后书': '2PE',
  '约翰一书': '1JN',
  '约翰二书': '2JN',
  '约翰三书': '3JN',
  '犹大书': 'JUD',
  '启示录': 'REV',
};

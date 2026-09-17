import 'dart:convert';

import '../../plans/domain/plan_models.dart';
import '../../plans/domain/plan_task_chapter_groups.dart';

final class DevotionManifest {
  const DevotionManifest({required this.revision, required this.years});

  final int revision;
  final List<DevotionYear> years;

  DevotionDay? dayFor(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    for (final year in years) {
      for (final day in year.days) {
        if (day.date == date) return day;
      }
    }
    return null;
  }

  static DevotionManifest parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid devotion JSON: ${error.message}');
    }
    return _DevotionManifestParser.parse(decoded);
  }
}

final class DevotionYear {
  DevotionYear({required this.year, required List<DevotionDay> days})
    : days = List.unmodifiable(days);

  final int year;
  final List<DevotionDay> days;
}

final class DevotionDay {
  DevotionDay({required this.date, required List<DevotionPassage> passages})
    : passages = List.unmodifiable(passages);

  final DateTime date;
  final List<DevotionPassage> passages;

  List<PlanTaskChapterGroup> chapterGroups() {
    final groups = <PlanTaskChapterGroup>[];
    for (var passageIndex = 0; passageIndex < passages.length; passageIndex++) {
      final passage = passages[passageIndex];
      for (
        var chapter = passage.startChapter;
        chapter <= passage.endChapter;
        chapter++
      ) {
        final block = PlanTaskBlock(
          id: 0,
          taskId: 0,
          sortOrder: passageIndex,
          bookId: passage.bookId,
          startChapter: chapter,
          startVerse: chapter == passage.startChapter ? passage.startVerse : 1,
          endChapter: chapter,
          endVerse: chapter == passage.endChapter
              ? passage.endVerse
              : devotionChapterVerseCount(passage.bookId, chapter),
        );
        final existing = groups.indexWhere(
          (group) => group.bookId == passage.bookId && group.chapter == chapter,
        );
        if (existing == -1) {
          groups.add(
            PlanTaskChapterGroup(
              bookId: passage.bookId,
              chapter: chapter,
              blocks: [block],
            ),
          );
        } else {
          final group = groups[existing];
          groups[existing] = PlanTaskChapterGroup(
            bookId: group.bookId,
            chapter: group.chapter,
            blocks: [...group.blocks, block],
          );
        }
      }
    }
    return List.unmodifiable(groups);
  }
}

final class DevotionPassage {
  const DevotionPassage({
    required this.bookId,
    required this.startChapter,
    required this.startVerse,
    required this.endChapter,
    required this.endVerse,
  });

  final String bookId;
  final int startChapter;
  final int startVerse;
  final int endChapter;
  final int endVerse;

  Map<String, Object> toJson() => {
    'bookId': bookId,
    'startChapter': startChapter,
    'startVerse': startVerse,
    'endChapter': endChapter,
    'endVerse': endVerse,
  };
}

final class _DevotionManifestParser {
  static DevotionManifest parse(Object? value) {
    final root = _map(value, 'root');
    if (_string(root['format'], 'format') != 'bible-recite-devotion-plans') {
      throw const FormatException('Unsupported devotion format');
    }
    if (_integer(root['version'], 'version') != 1) {
      throw const FormatException('Unsupported devotion version');
    }
    final revision = _integer(root['revision'], 'revision');
    if (revision < 1) throw const FormatException('Revision must be positive');
    final years = _list(
      root['years'],
      'years',
    ).map((raw) => _year(_map(raw, 'year'))).toList(growable: false);
    if (years.isEmpty ||
        years.map((year) => year.year).toSet().length != years.length) {
      throw const FormatException('Years must be present and unique');
    }
    return DevotionManifest(
      revision: revision,
      years: List.unmodifiable(years),
    );
  }

  static DevotionYear _year(Map<String, Object?> value) {
    final year = _integer(value['year'], 'year');
    if (year < 1 || year > 9999) throw const FormatException('Invalid year');
    final days = _list(
      value['days'],
      'days',
    ).map((raw) => _day(_map(raw, 'day'), year)).toList(growable: false);
    final expected = DateTime(year, 1, 1);
    final count = DateTime(year + 1, 1, 1).difference(expected).inDays;
    if (days.length != count) {
      throw FormatException('Year $year is incomplete');
    }
    for (var index = 0; index < days.length; index++) {
      if (days[index].date != expected.add(Duration(days: index))) {
        throw FormatException('Year $year days must be unique and complete');
      }
    }
    return DevotionYear(year: year, days: days);
  }

  static DevotionDay _day(Map<String, Object?> value, int year) {
    final date = _date(_string(value['date'], 'date'));
    if (date.year != year) {
      throw const FormatException('Day is outside its year');
    }
    final passages = _list(
      value['passages'],
      'passages',
    ).map((raw) => _passage(_map(raw, 'passage'))).toList(growable: false);
    if (passages.isEmpty) {
      throw const FormatException('Day needs a passage');
    }
    return DevotionDay(date: date, passages: passages);
  }

  static DevotionPassage _passage(Map<String, Object?> value) {
    final bookId = _string(value['bookId'], 'bookId');
    final startChapter = _integer(value['startChapter'], 'startChapter');
    final startVerse = _integer(value['startVerse'], 'startVerse');
    final endChapter = _integer(value['endChapter'], 'endChapter');
    final endVerse = _integer(value['endVerse'], 'endVerse');
    if (!_chapterCounts.containsKey(bookId) ||
        startChapter < 1 ||
        endChapter < startChapter ||
        endChapter > _chapterCounts[bookId]! ||
        startVerse < 1 ||
        endVerse < 1 ||
        startVerse > devotionChapterVerseCount(bookId, startChapter) ||
        endVerse > devotionChapterVerseCount(bookId, endChapter) ||
        (startChapter == endChapter && endVerse < startVerse)) {
      throw const FormatException('Invalid devotion passage range');
    }
    return DevotionPassage(
      bookId: bookId,
      startChapter: startChapter,
      startVerse: startVerse,
      endChapter: endChapter,
      endVerse: endVerse,
    );
  }
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$field must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String field) {
  if (value is! List<Object?>) {
    throw FormatException('$field must be a list');
  }
  return value;
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

int _integer(Object? value, String field) {
  if (value is! int) {
    throw FormatException('$field must be an integer');
  }
  return value;
}

DateTime _date(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid ISO date');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    throw const FormatException('Invalid calendar date');
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

int devotionChapterVerseCount(String bookId, int chapter) =>
    _chapterVerseCounts[bookId]?[chapter - 1] ?? 176;

const _chapterCounts = <String, int>{
  'GEN': 50,
  'EXO': 40,
  'LEV': 27,
  'NUM': 36,
  'DEU': 34,
  'JOS': 24,
  'JDG': 21,
  'RUT': 4,
  '1SA': 31,
  '2SA': 24,
  '1KI': 22,
  '2KI': 25,
  '1CH': 29,
  '2CH': 36,
  'EZR': 10,
  'NEH': 13,
  'EST': 10,
  'JOB': 42,
  'PSA': 150,
  'PRO': 31,
  'ECC': 12,
  'SNG': 8,
  'ISA': 66,
  'JER': 52,
  'LAM': 5,
  'EZK': 48,
  'DAN': 12,
  'HOS': 14,
  'JOL': 3,
  'AMO': 9,
  'OBA': 1,
  'JON': 4,
  'MIC': 7,
  'NAM': 3,
  'HAB': 3,
  'ZEP': 3,
  'HAG': 2,
  'ZEC': 14,
  'MAL': 4,
  'MAT': 28,
  'MRK': 16,
  'LUK': 24,
  'JHN': 21,
  'ACT': 28,
  'ROM': 16,
  '1CO': 16,
  '2CO': 13,
  'GAL': 6,
  'EPH': 6,
  'PHP': 4,
  'COL': 4,
  '1TH': 5,
  '2TH': 3,
  '1TI': 6,
  '2TI': 4,
  'TIT': 3,
  'PHM': 1,
  'HEB': 13,
  'JAS': 5,
  '1PE': 5,
  '2PE': 3,
  '1JN': 5,
  '2JN': 1,
  '3JN': 1,
  'JUD': 1,
  'REV': 22,
};

const _chapterVerseCounts = <String, List<int>>{
  'EZR': [11, 70, 13, 24, 17, 22, 28, 36, 15, 44],
  'NEH': [11, 20, 32, 23, 19, 19, 73, 18, 38, 39, 36, 47, 31],
  'EST': [22, 23, 15, 17, 14, 14, 10, 17, 32, 3],
  'JOB': [
    22,
    13,
    26,
    21,
    27,
    30,
    21,
    22,
    35,
    22,
    20,
    25,
    28,
    22,
    35,
    22,
    16,
    21,
    29,
    29,
    34,
    30,
    17,
    25,
    6,
    14,
    23,
    28,
    25,
    31,
    40,
    22,
    33,
    37,
    16,
    33,
    24,
    41,
    30,
    24,
    34,
    17,
  ],
  'PSA': [
    6,
    12,
    8,
    8,
    12,
    10,
    17,
    9,
    20,
    18,
    7,
    8,
    6,
    7,
    5,
    11,
    15,
    50,
    14,
    9,
    13,
    31,
    6,
    10,
    22,
    12,
    14,
    9,
    11,
    12,
    24,
    11,
    22,
    22,
    28,
    12,
    40,
    22,
    13,
    17,
    13,
    11,
    5,
    26,
    17,
    11,
    9,
    14,
    20,
    23,
    19,
    9,
    6,
    7,
    23,
    13,
    11,
    11,
    17,
    12,
    8,
    12,
    11,
    10,
    13,
    20,
    7,
    35,
    36,
    5,
    24,
    20,
    28,
    23,
    10,
    12,
    20,
    72,
    13,
    19,
    16,
    8,
    18,
    12,
    13,
    17,
    7,
    18,
    52,
    17,
    16,
    15,
    5,
    23,
    11,
    13,
    12,
    9,
    9,
    5,
    8,
    28,
    22,
    35,
    45,
    48,
    43,
    13,
    31,
    7,
    10,
    10,
    9,
    8,
    18,
    19,
    2,
    29,
    176,
    7,
    8,
    9,
    4,
    8,
    5,
    6,
    5,
    6,
    8,
    8,
    3,
    18,
    3,
    3,
    21,
    26,
    9,
    8,
    24,
    13,
    10,
    7,
    12,
    15,
    21,
    10,
    20,
    14,
    9,
    6,
  ],
  'PRO': [
    33,
    22,
    35,
    27,
    23,
    35,
    27,
    36,
    18,
    32,
    31,
    28,
    25,
    35,
    33,
    33,
    28,
    24,
    29,
    30,
    31,
    29,
    35,
    34,
    28,
    28,
    27,
    28,
    27,
    33,
    31,
  ],
  'ECC': [18, 26, 22, 16, 20, 12, 29, 17, 18, 20, 10, 14],
  'SNG': [17, 17, 11, 16, 16, 13, 13, 14],
  'ISA': [
    31,
    22,
    26,
    6,
    30,
    13,
    25,
    22,
    21,
    34,
    16,
    6,
    22,
    32,
    9,
    14,
    14,
    7,
    25,
    6,
    17,
    25,
    18,
    23,
    12,
    21,
    13,
    29,
    24,
    33,
    9,
    20,
    24,
    17,
    10,
    22,
    38,
    22,
    8,
    31,
    29,
    25,
    28,
    28,
    25,
    13,
    15,
    22,
    26,
    11,
    23,
    15,
    12,
    17,
    13,
    12,
    21,
    14,
    21,
    22,
    11,
    12,
    19,
    12,
    25,
    24,
  ],
  'JER': [
    19,
    37,
    25,
    31,
    31,
    30,
    34,
    22,
    26,
    25,
    23,
    17,
    27,
    22,
    21,
    21,
    27,
    23,
    15,
    18,
    14,
    30,
    40,
    10,
    38,
    24,
    22,
    17,
    32,
    24,
    40,
    44,
    26,
    22,
    19,
    32,
    21,
    28,
    18,
    16,
    18,
    22,
    13,
    30,
    5,
    28,
    7,
    47,
    39,
    46,
    64,
    34,
  ],
  'JHN': [
    51,
    25,
    36,
    54,
    46,
    71,
    52,
    59,
    41,
    42,
    57,
    50,
    38,
    31,
    27,
    33,
    26,
    40,
    42,
    31,
    25,
  ],
};

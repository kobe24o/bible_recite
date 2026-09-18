import 'dart:convert';

import '../../scripture/domain/canonical_verse_limits.dart'
    show canonicalProtestant66VerseLimits;
import '../../plans/domain/plan_models.dart';
import '../../plans/domain/plan_task_chapter_groups.dart';

final class DevotionManifest {
  DevotionManifest({required this.revision, required List<DevotionYear> years})
    : years = List.unmodifiable(years);

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
    final chapterVerseLimits = canonicalProtestant66VerseLimits[bookId];
    if (chapterVerseLimits == null ||
        startChapter < 1 ||
        endChapter < startChapter ||
        endChapter > chapterVerseLimits.length ||
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

int devotionChapterVerseCount(String bookId, int chapter) {
  final limits = canonicalProtestant66VerseLimits[bookId];
  if (limits == null || chapter < 1 || chapter > limits.length) {
    throw ArgumentError.value(
      (bookId: bookId, chapter: chapter),
      'chapter',
      'Unknown book or chapter',
    );
  }
  return limits[chapter - 1];
}

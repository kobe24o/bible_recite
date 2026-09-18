import 'dart:convert';
import 'dart:io';

import 'package:bible_recite/src/features/devotion/domain/devotion_models.dart';

Future<void> main(List<String> arguments) async {
  final options = _options(arguments);
  final input = options['input'];
  final output = options['output'];
  final revision = int.tryParse(options['revision'] ?? '');
  if (input == null || output == null || revision == null || revision < 1) {
    throw ArgumentError(
      'Usage: --input SOURCE --output devotion-plans.json --revision POSITIVE_INT',
    );
  }
  await publish2026Devotion(
    input: File(input),
    output: File(output),
    revision: revision,
  );
}

Future<void> publish2026Devotion({
  required File input,
  required File output,
  required int revision,
}) async {
  if (revision < 1) throw const FormatException('Revision must be positive');
  final days = _parseSource(await input.readAsString());
  _validateComplete2026(days);
  final encoded = const JsonEncoder.withIndent('  ').convert({
    'format': 'bible-recite-devotion-plans',
    'version': 1,
    'revision': revision,
    'years': [
      {
        'year': 2026,
        'days': [
          for (final day in days)
            {
              'date': _dateLabel(day.date),
              'passages': [
                for (final passage in day.passages) passage.toJson(),
              ],
            },
        ],
      },
    ],
  });
  final parent = output.parent;
  if (!await parent.exists()) await parent.create(recursive: true);
  final temporary = File('${output.path}.tmp');
  await temporary.writeAsString('$encoded\n', flush: true);
  await temporary.rename(output.path);
}

List<_SourceDay> _parseSource(String source) {
  final dates = RegExp(
    r'(\d{4})年(\d{1,2})月(\d{1,2})日',
  ).allMatches(source).toList();
  if (dates.isEmpty) throw const FormatException('No dates found in source');
  final days = <_SourceDay>[];
  for (var index = 0; index < dates.length; index++) {
    final match = dates[index];
    final date = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    if (_dateLabel(date) !=
        '${match.group(1)!.padLeft(4, '0')}-${match.group(2)!.padLeft(2, '0')}-${match.group(3)!.padLeft(2, '0')}') {
      throw FormatException('Invalid date ${match.group(0)}');
    }
    final end = index + 1 < dates.length
        ? dates[index + 1].start
        : source.length;
    final entry = source.substring(match.end, end).trim();
    final bookName = _bookNames.keys.firstWhere(
      entry.startsWith,
      orElse: () => throw FormatException('Unknown Chinese book in $entry'),
    );
    final reference = entry.substring(bookName.length).trim();
    if (reference.isEmpty) {
      throw FormatException('Missing passage for ${match.group(0)}');
    }
    days.add(
      _SourceDay(date, _parsePassages(_bookNames[bookName]!, reference)),
    );
  }
  days.sort((left, right) => left.date.compareTo(right.date));
  return days;
}

List<DevotionPassage> _parsePassages(String bookId, String source) {
  return source
      .split('、')
      .map((part) {
        final value = part.trim();
        final fullRange = RegExp(r'^(\d+)(?:-(\d+))?章$').firstMatch(value);
        if (fullRange != null) {
          final start = int.parse(fullRange.group(1)!);
          final end = int.parse(fullRange.group(2) ?? fullRange.group(1)!);
          _validateChapterRange(bookId, start, end);
          return DevotionPassage(
            bookId: bookId,
            startChapter: start,
            startVerse: 1,
            endChapter: end,
            endVerse: devotionChapterVerseCount(bookId, end),
          );
        }
        final verses = RegExp(
          r'^(\d+):(\d+)-(?:((\d+)):)?(\d+)$',
        ).firstMatch(value);
        if (verses == null) {
          throw FormatException('Unsupported passage: $value');
        }
        final startChapter = int.parse(verses.group(1)!);
        final startVerse = int.parse(verses.group(2)!);
        final endChapter = int.parse(verses.group(4) ?? verses.group(1)!);
        final endVerse = int.parse(verses.group(5)!);
        _validateChapterRange(bookId, startChapter, endChapter);
        if (startVerse < 1 ||
            endVerse < 1 ||
            startVerse > devotionChapterVerseCount(bookId, startChapter) ||
            endVerse > devotionChapterVerseCount(bookId, endChapter) ||
            (startChapter == endChapter && endVerse < startVerse)) {
          throw FormatException('Invalid verse range: $value');
        }
        return DevotionPassage(
          bookId: bookId,
          startChapter: startChapter,
          startVerse: startVerse,
          endChapter: endChapter,
          endVerse: endVerse,
        );
      })
      .toList(growable: false);
}

void _validateComplete2026(List<_SourceDay> days) {
  if (days.length != 365) {
    throw const FormatException('2026 requires 365 days');
  }
  final start = DateTime(2026, 1, 1);
  for (var index = 0; index < days.length; index++) {
    if (days[index].date != start.add(Duration(days: index))) {
      throw const FormatException(
        'Source has missing, duplicate, or invalid dates',
      );
    }
  }
}

void _validateChapterRange(String bookId, int start, int end) {
  if (start < 1 || end < start || end > _chapterCounts[bookId]!) {
    throw const FormatException('Invalid chapter range');
  }
}

String _dateLabel(DateTime value) => value.toIso8601String().substring(0, 10);

Map<String, String> _options(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (!arguments[index].startsWith('--') || index + 1 == arguments.length) {
      throw ArgumentError('Expected --name value arguments');
    }
    result[arguments[index].substring(2)] = arguments[index + 1];
  }
  return result;
}

final class _SourceDay {
  const _SourceDay(this.date, this.passages);

  final DateTime date;
  final List<DevotionPassage> passages;
}

const _bookNames = <String, String>{
  '耶利米哀歌': 'LAM',
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
};

const _chapterCounts = <String, int>{
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
};

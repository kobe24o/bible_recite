import 'dart:convert';

import 'package:bible_recite/src/features/devotion/domain/devotion_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses all 365 2026 days and preserves multi-passage dates', () {
    final manifest = DevotionManifest.parse(complete2026Json);

    expect(manifest.years.single.days, hasLength(365));
    final feb2 = manifest.dayFor(DateTime(2026, 2, 2))!;
    expect(feb2.passages.map((passage) => passage.bookId), ['EST', 'EST']);
    expect(feb2.passages.last.endChapter, 10);
  });

  test('rejects a missing calendar day', () {
    expect(
      () => DevotionManifest.parse(missingDateJson),
      throwsFormatException,
    );
  });

  test(
    'rejects a verse beyond the real chapter end for every accepted book',
    () {
      expect(
        () => DevotionManifest.parse(
          _jsonForDays({
            DateTime(2026, 1, 1): [_passage('JHN', 3, 1, 3, 37)],
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test('rejects an OSIS book without complete verse-count data', () {
    expect(
      () => DevotionManifest.parse(
        _jsonForDays({
          DateTime(2026, 1, 1): [_passage('GEN', 1, 1, 1, 31)],
        }),
      ),
      throwsFormatException,
    );
  });

  test('defensively freezes the manifest year list', () {
    final years = <DevotionYear>[];
    final manifest = DevotionManifest(revision: 1, years: years);

    years.add(DevotionYear(year: 2026, days: const []));

    expect(manifest.years, isEmpty);
  });

  test('splits cross chapter ranges at real chapter ends', () {
    final manifest = DevotionManifest.parse(
      _jsonForDays({
        DateTime(2026, 1, 1): [_passage('JHN', 3, 16, 4, 3)],
      }),
    );

    final groups = manifest.dayFor(DateTime(2026, 1, 1))!.chapterGroups();
    expect(groups, hasLength(2));
    expect(groups.first.bookId, 'JHN');
    expect(groups.first.chapter, 3);
    expect(groups.first.includesVerse(15), isFalse);
    expect(groups.first.includesVerse(16), isTrue);
    expect(groups.first.includesVerse(36), isTrue);
    expect(groups[1].chapter, 4);
    expect(groups[1].includesVerse(3), isTrue);
    expect(groups[1].includesVerse(4), isFalse);
  });
}

final complete2026Json = _jsonForDays({
  DateTime(2026, 2, 2): [
    _passage('EST', 9, 17, 9, 32),
    _passage('EST', 10, 1, 10, 3),
  ],
});

final missingDateJson = _jsonForDays({}, omit: DateTime(2026, 6, 1));

String _jsonForDays(
  Map<DateTime, List<Map<String, Object>>> overrides, {
  DateTime? omit,
}) {
  final start = DateTime(2026, 1, 1);
  final days = <Map<String, Object>>[];
  for (var offset = 0; offset < 365; offset++) {
    final date = start.add(Duration(days: offset));
    if (date == omit) continue;
    days.add({
      'date': date.toIso8601String().substring(0, 10),
      'passages': overrides[date] ?? [_passage('EZR', 1, 1, 1, 11)],
    });
  }
  return jsonEncode({
    'format': 'bible-recite-devotion-plans',
    'version': 1,
    'revision': 1,
    'years': [
      {'year': 2026, 'days': days},
    ],
  });
}

Map<String, Object> _passage(
  String bookId,
  int startChapter,
  int startVerse,
  int endChapter,
  int endVerse,
) => {
  'bookId': bookId,
  'startChapter': startChapter,
  'startVerse': startVerse,
  'endChapter': endChapter,
  'endVerse': endVerse,
};

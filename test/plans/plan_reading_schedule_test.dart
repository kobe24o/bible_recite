import 'package:flutter_test/flutter_test.dart';
import 'package:bible_recite/src/features/plans/domain/plan_reading_schedule.dart';

void main() {
  test(
    'daily quotas carry across chapter boundaries and keep the remainder',
    () {
      expect(
        distributeReadingUnits(
          [1, 2, 3, 4, 5],
          ReadingScheduleMode.dailyVerses,
          2,
        ),
        [
          [1, 2],
          [3, 4],
          [5],
        ],
      );
    },
  );
  test('fixed days distribute by count rather than text length', () {
    expect(
      distributeReadingUnits(
        [1, 2, 3, 4, 5],
        ReadingScheduleMode.daysByVerses,
        3,
      ),
      [
        [1, 2],
        [3, 4],
        [5],
      ],
    );
  });
  test('chapter allocation never splits a chapter', () {
    expect(
      distributeReadingUnits(
        ['a', 'b', 'c', 'd', 'e'],
        ReadingScheduleMode.daysByChapters,
        2,
      ),
      [
        ['a', 'b', 'c'],
        ['d', 'e'],
      ],
    );
  });
  test('more days than units retains empty days at the end', () {
    expect(
      distributeReadingUnits([1, 2], ReadingScheduleMode.daysByVerses, 4),
      [
        [1],
        [2],
        [],
        [],
      ],
    );
  });
  test('nonpositive quota is rejected', () {
    expect(
      () => distributeReadingUnits([1], ReadingScheduleMode.dailyChapters, 0),
      throwsArgumentError,
    );
  });
}

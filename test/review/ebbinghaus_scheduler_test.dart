import 'package:bible_recite/src/features/review/domain/ebbinghaus_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the fixed 1 2 4 7 15 30 day review curve', () {
    final dates = const EbbinghausScheduler().reviewDates(
      DateTime(2026, 7, 16),
    );

    expect(
      dates,
      [
        1,
        2,
        4,
        7,
        15,
        30,
      ].map((days) => DateTime(2026, 7, 16).add(Duration(days: days))).toList(),
    );
  });

  test('passes at or above the configured accuracy threshold', () {
    const scheduler = EbbinghausScheduler();

    expect(scheduler.passes(accuracy: 0.79, threshold: 0.80), isFalse);
    expect(scheduler.passes(accuracy: 0.80, threshold: 0.80), isTrue);
    expect(scheduler.passes(accuracy: 0.91, threshold: 0.80), isTrue);
  });
}

import 'package:bible_recite/src/app/runtime_platform.dart';
import 'package:bible_recite/src/features/reminder/daily_task_reminder.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses Darwin notification initialization on iOS', () {
    final settings = dailyTaskReminderInitializationSettings(
      AppRuntimePlatform.ios,
    );

    expect(settings.iOS, isA<DarwinInitializationSettings>());
    expect(settings.android, isNull);
  });

  test('moves the next reminder to tomorrow after today window has ended', () {
    final settings = DailyTaskReminderSettings(
      enabled: true,
      startMinutes: 9 * 60,
      endMinutes: 18 * 60,
      intervalMinutes: 60,
    );

    final slots = reminderSlots(
      now: DateTime(2026, 7, 30, 19),
      settings: settings,
      maxSlots: 3,
    );

    expect(slots.first, DateTime(2026, 7, 31, 9));
    expect(slots, [
      DateTime(2026, 7, 31, 9),
      DateTime(2026, 7, 31, 10),
      DateTime(2026, 7, 31, 11),
    ]);
  });
}

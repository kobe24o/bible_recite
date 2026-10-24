import 'package:bible_recite/src/app/runtime_platform.dart';
import 'package:bible_recite/src/features/reminder/daily_task_reminder.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one unfinished devotion counts as a learning reminder', () {
    expect(
      pendingLearningItemCount(tasks: 0, reviews: 0, devotionPending: true),
      1,
    );
  });

  test('uses Darwin notification initialization on iOS', () {
    final settings = dailyTaskReminderInitializationSettings(
      AppRuntimePlatform.ios,
    );

    expect(settings.iOS, isA<DarwinInitializationSettings>());
    expect(settings.android, isNull);
  });

  test('initializes native notifications on macOS and Windows', () {
    final mac = dailyTaskReminderInitializationSettings(
      AppRuntimePlatform.macos,
    );
    expect(mac.macOS, isA<DarwinInitializationSettings>());
    expect(mac.iOS, isNull);
    expect(mac.macOS!.requestAlertPermission, isTrue);
    final windows = dailyTaskReminderInitializationSettings(
      AppRuntimePlatform.windows,
    );
    expect(windows.windows!.appName, '背诵助手');
    expect(windows.windows!.appUserModelId, 'app.biblerecite.desktop');
    expect(windows.windows!.guid, matches(RegExp(r'^[0-9a-f-]{36}$')));
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

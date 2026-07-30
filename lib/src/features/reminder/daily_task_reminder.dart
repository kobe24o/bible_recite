import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../plans/data/sqlite_plan_repository.dart';

final class DailyTaskReminderSettings {
  const DailyTaskReminderSettings({
    required this.enabled,
    required this.startMinutes,
    required this.endMinutes,
    required this.intervalMinutes,
  });

  final bool enabled;
  final int startMinutes;
  final int endMinutes;
  final int intervalMinutes;

  DailyTaskReminderSettings copyWith({
    bool? enabled,
    int? startMinutes,
    int? endMinutes,
    int? intervalMinutes,
  }) => DailyTaskReminderSettings(
    enabled: enabled ?? this.enabled,
    startMinutes: startMinutes ?? this.startMinutes,
    endMinutes: endMinutes ?? this.endMinutes,
    intervalMinutes: intervalMinutes ?? this.intervalMinutes,
  );
}

final class DailyTaskReminderScheduler {
  DailyTaskReminderScheduler({FlutterLocalNotificationsPlugin? notifications})
    : _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'daily_task_reminders';
  static const _notificationBaseId = 7100;
  final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;

  Future<void> initialize() async {
    // The app currently distributes the reminder feature on Android only.
    // Avoid creating an Android plugin instance on desktop/test hosts.
    if (!Platform.isAndroid) return;
    if (_initialized) return;
    tz.initializeTimeZones();
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher_bible'),
      ),
    );
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> reschedule(SqlitePlanRepository repository) async {
    if (!Platform.isAndroid) return;
    await initialize();
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final allowed = await android?.areNotificationsEnabled();
    if (allowed == false) return;
    for (var index = 0; index < 32; index++) {
      await _notifications.cancel(id: _notificationBaseId + index);
    }
    final settings = await readSettings(repository);
    if (!settings.enabled || settings.intervalMinutes <= 0) return;
    final now = DateTime.now();
    final pending = await repository.dueTasks(now);
    if (pending.isEmpty) return;
    final slots = reminderSlots(now: now, settings: settings, maxSlots: 32);
    for (var index = 0; index < slots.length; index++) {
      await _notifications.zonedSchedule(
        id: _notificationBaseId + index,
        title: '背诵助手',
        body: '今天还有 ${pending.length} 项背诵任务未完成',
        scheduledDate: tz.TZDateTime.from(slots[index], tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '今日背诵提醒',
            channelDescription: '提醒完成当天的背诵计划',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static Future<DailyTaskReminderSettings> readSettings(
    SqlitePlanRepository repository,
  ) async => DailyTaskReminderSettings(
    enabled:
        await repository.getSetting('daily_reminder_enabled', 'true') == 'true',
    startMinutes:
        int.tryParse(
          await repository.getSetting('daily_reminder_start', '420'),
        ) ??
        420,
    endMinutes:
        int.tryParse(
          await repository.getSetting('daily_reminder_end', '1439'),
        ) ??
        1439,
    intervalMinutes:
        int.tryParse(
          await repository.getSetting('daily_reminder_interval', '60'),
        ) ??
        60,
  );

  static Future<void> saveSettings(
    SqlitePlanRepository repository,
    DailyTaskReminderSettings settings,
  ) async {
    await repository.setSetting(
      'daily_reminder_enabled',
      settings.enabled ? 'true' : 'false',
    );
    await repository.setSetting(
      'daily_reminder_start',
      settings.startMinutes.toString(),
    );
    await repository.setSetting(
      'daily_reminder_end',
      settings.endMinutes.toString(),
    );
    await repository.setSetting(
      'daily_reminder_interval',
      settings.intervalMinutes.toString(),
    );
  }

}

List<DateTime> reminderSlots({
  required DateTime now,
  required DailyTaskReminderSettings settings,
  required int maxSlots,
}) {
  if (!settings.enabled || settings.intervalMinutes <= 0 || maxSlots <= 0) {
    return const [];
  }
  final slots = <DateTime>[];
  var day = DateTime(now.year, now.month, now.day);
  while (slots.length < maxSlots) {
    final first = day.add(Duration(minutes: settings.startMinutes));
    final last = day.add(Duration(minutes: settings.endMinutes));
    for (var time = first; !time.isAfter(last); time = time.add(Duration(minutes: settings.intervalMinutes))) {
      if (time.isAfter(now)) slots.add(time);
      if (slots.length == maxSlots) return slots;
    }
    day = day.add(const Duration(days: 1));
  }
  return slots;
}

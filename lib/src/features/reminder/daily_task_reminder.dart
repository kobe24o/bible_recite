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
    await _notifications.cancelAll();
    final settings = await readSettings(repository);
    if (!settings.enabled || settings.intervalMinutes <= 0) return;
    final now = DateTime.now();
    final pending = await repository.dueTasks(now);
    if (pending.isEmpty) return;
    final today = tz.TZDateTime.now(tz.local);
    final first = _at(today, settings.startMinutes);
    final last = _at(today, settings.endMinutes);
    var scheduled = first.isAfter(today)
        ? first
        : today.add(const Duration(minutes: 1));
    var index = 0;
    while (!scheduled.isAfter(last) && index < 32) {
      await _notifications.zonedSchedule(
        id: _notificationBaseId + index,
        title: '背诵助手',
        body: '今天还有 ${pending.length} 项背诵任务未完成',
        scheduledDate: scheduled,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '今日背诵提醒',
            channelDescription: '提醒完成当天的背诵计划',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      scheduled = scheduled.add(Duration(minutes: settings.intervalMinutes));
      index++;
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

  tz.TZDateTime _at(tz.TZDateTime today, int minutes) => tz.TZDateTime(
    tz.local,
    today.year,
    today.month,
    today.day,
    minutes ~/ 60,
    minutes % 60,
  );
}

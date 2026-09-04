import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../app/runtime_platform.dart';
import '../plans/data/sqlite_plan_repository.dart';

InitializationSettings dailyTaskReminderInitializationSettings(
  AppRuntimePlatform platform,
) => switch (platform) {
  AppRuntimePlatform.android => const InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher_bible'),
  ),
  AppRuntimePlatform.ios => const InitializationSettings(
    iOS: DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    ),
  ),
  AppRuntimePlatform.other => const InitializationSettings(),
};

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
  DailyTaskReminderScheduler({
    FlutterLocalNotificationsPlugin? notifications,
    AppRuntimePlatform? platform,
  }) : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _platform = platform ?? detectRuntimePlatform();

  // A new channel restores high-priority delivery on devices where users or
  // OEM settings previously downgraded the old channel.
  static const _channelId = 'daily_task_reminders_v2';
  static const _notificationBaseId = 7100;
  final FlutterLocalNotificationsPlugin _notifications;
  final AppRuntimePlatform _platform;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_platform == AppRuntimePlatform.other) return;
    if (_initialized) return;
    tz.initializeTimeZones();
    await _notifications.initialize(
      settings: dailyTaskReminderInitializationSettings(_platform),
    );
    if (_platform == AppRuntimePlatform.android) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();
    }
    _initialized = true;
  }

  Future<void> reschedule(SqlitePlanRepository repository) async {
    if (_platform == AppRuntimePlatform.other) return;
    await initialize();
    AndroidFlutterLocalNotificationsPlugin? android;
    if (_platform == AppRuntimePlatform.android) {
      android = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final allowed = await android?.areNotificationsEnabled();
      if (allowed == false) return;
    }
    for (var index = 0; index < 32; index++) {
      await _notifications.cancel(id: _notificationBaseId + index);
    }
    final settings = await readSettings(repository);
    if (!settings.enabled || settings.intervalMinutes <= 0) return;
    final now = DateTime.now();
    final pendingTasks = await repository.dueTasks(now);
    final pendingReviews = await repository.dueEbbinghausReviews(now);
    final pendingCount = pendingTasks.length + pendingReviews.length;
    if (pendingCount == 0) return;
    if (_platform == AppRuntimePlatform.android) {
      // Inexact alarms can be deferred while Android is idle. Ask only when a
      // reminder is actually needed, then the app lifecycle callback will
      // schedule the alarms as soon as the user returns from Android settings.
      if (await android?.canScheduleExactNotifications() == false) {
        await android?.requestExactAlarmsPermission();
        return;
      }
    }
    final slots = reminderSlots(now: now, settings: settings, maxSlots: 32);
    for (var index = 0; index < slots.length; index++) {
      await _notifications.zonedSchedule(
        id: _notificationBaseId + index,
        title: '背诵助手',
        body: '今天还有 $pendingCount 项背诵任务未完成',
        scheduledDate: tz.TZDateTime.from(slots[index], tz.local),
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  NotificationDetails get _notificationDetails => switch (_platform) {
    AppRuntimePlatform.android => const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        '今日背诵提醒',
        channelDescription: '提醒完成当天的背诵计划',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
    ),
    AppRuntimePlatform.ios => const NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
      ),
    ),
    AppRuntimePlatform.other => const NotificationDetails(),
  };

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
    for (
      var time = first;
      !time.isAfter(last);
      time = time.add(Duration(minutes: settings.intervalMinutes))
    ) {
      if (time.isAfter(now)) slots.add(time);
      if (slots.length == maxSlots) return slots;
    }
    day = day.add(const Duration(days: 1));
  }
  return slots;
}

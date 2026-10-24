import 'package:bible_recite/src/app/runtime_platform.dart';
import 'package:bible_recite/src/features/reminder/daily_task_reminder.dart';
import 'package:bible_recite/src/features/reminder/reminder_providers.dart';

// Widget tests have no OS notification plugin. Native coverage lives in
// integration_test/desktop_smoke_test.dart and runs on real desktop runners.
final noNativeReminders = dailyTaskReminderSchedulerProvider.overrideWithValue(
  DailyTaskReminderScheduler(platform: AppRuntimePlatform.other),
);

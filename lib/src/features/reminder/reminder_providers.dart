import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'daily_task_reminder.dart';

final dailyTaskReminderSchedulerProvider = Provider<DailyTaskReminderScheduler>(
  (ref) => DailyTaskReminderScheduler(),
);

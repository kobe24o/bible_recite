import 'dart:io';

import 'package:bible_recite/src/app/responsive_shell.dart';
import 'package:bible_recite/src/app/runtime_platform.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/recitation/data/sherpa_streaming_recognizer.dart';
import 'package:bible_recite/src/features/reminder/daily_task_reminder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'desktop engine loads storage, speech, notifications and navigation',
    (tester) async {
      expect(Platform.isWindows || Platform.isMacOS, isTrue);
      expect(
        detectRuntimePlatform(),
        Platform.isMacOS
            ? AppRuntimePlatform.macos
            : AppRuntimePlatform.windows,
      );
      final info = await PackageInfo.fromPlatform();
      expect(info.version, isNotEmpty);
      final support = await getApplicationSupportDirectory();
      expect(await support.exists(), isTrue);
      // Use a unique scratch database; never change an installed user's history.
      final scratch = await Directory.systemTemp.createTemp(
        'bible-desktop-smoke-',
      );
      try {
        final path = '${scratch.path}/smoke.sqlite';
        var repository = SqlitePlanRepository(sqlite3.open(path));
        await repository.setSetting('profile_name', 'Desktop smoke');
        repository.close();
        repository = SqlitePlanRepository(sqlite3.open(path));
        try {
          expect(
            await repository.getSetting('profile_name', ''),
            'Desktop smoke',
          );
        } finally {
          repository.close();
        }
      } finally {
        await scratch.delete(recursive: true);
      }

      final recorder = AudioRecorder();
      try {
        // Exercise plugin registration without requesting microphone permission.
        expect(
          await recorder.isEncoderSupported(AudioEncoder.pcm16bits),
          isTrue,
        );
      } finally {
        await recorder.dispose();
      }
      final recognizer = SherpaStreamingRecognizer();
      try {
        // Actually load the bundled ONNX model and native library on each OS.
        await recognizer.initialize();
      } finally {
        await recognizer.dispose();
      }

      final defaults = dailyTaskReminderInitializationSettings(
        detectRuntimePlatform(),
      );
      final notifications = FlutterLocalNotificationsPlugin();
      final initialized = await notifications.initialize(
        settings: InitializationSettings(
          windows: defaults.windows,
          macOS: const DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      // macOS returns false if notification permission is denied, including on
      // an unattended runner. Initialization must still complete without error.
      if (Platform.isWindows) expect(initialized, isTrue);
      await notifications.pendingNotificationRequests();

      await tester.pumpWidget(
        const MaterialApp(home: ResponsiveShell(child: Text('桌面启动成功'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('桌面启动成功'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

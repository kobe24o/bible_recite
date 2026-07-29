import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/update_manifest.dart';

final class UpdateAvailableNotification {
  static const _id = 7200;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> show(UpdateManifest manifest) async {
    if (!Platform.isAndroid) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher_bible'),
      ),
    );
    await _plugin.show(
      id: _id,
      title: 'Bible Recite 有新版本',
      body: '发现 ${manifest.version}，打开应用即可下载更新。',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'app_updates',
          '应用更新',
          channelDescription: '发现新版本时通知',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }
}

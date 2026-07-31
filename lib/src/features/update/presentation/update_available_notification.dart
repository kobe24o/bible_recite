import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../app/router.dart';
import '../domain/update_manifest.dart';

final class UpdateAvailableNotification {
  static const _id = 7200;
  static const _openAboutPayload = 'open-update-about';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher_bible'),
      ),
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    _initialized = true;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _handleNotificationResponse(launchDetails!.notificationResponse!);
    }
  }

  static void _handleNotificationResponse(NotificationResponse response) =>
      handlePayload(response.payload);

  /// Defers routing until after the app's router has attached during a
  /// notification-driven cold start or resume.
  static void handlePayload(String? payload) {
    if (payload != _openAboutPayload) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => openUpdatePage());
    WidgetsBinding.instance.scheduleFrame();
  }

  static void openUpdatePage() => appRouter.go('/about');

  Future<void> show(UpdateManifest manifest) async {
    if (!Platform.isAndroid) return;
    await initialize();
    await _plugin.show(
      id: _id,
      title: 'Bible Recite 有新版本',
      body: '发现 ${manifest.version}，打开应用即可下载更新。',
      payload: _openAboutPayload,
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

  Future<void> showDownloaded(UpdateManifest manifest) async {
    if (!Platform.isAndroid) return;
    await initialize();
    await _plugin.show(
      id: _id,
      title: 'Bible Recite 更新已下载',
      body: '${manifest.version} 已在 Wi-Fi 下下载完成，点此安装。',
      payload: _openAboutPayload,
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

import 'dart:io';

import 'package:flutter/services.dart';

final class AndroidApkInfo {
  const AndroidApkInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.certificateSha256,
  });

  factory AndroidApkInfo.fromChannelMap(Map<Object?, Object?> values) {
    final packageName = values['packageName'];
    final versionName = values['versionName'];
    final versionCode = values['versionCode'];
    final certificateSha256 = values['certificateSha256'];
    if (packageName is! String ||
        versionName is! String ||
        versionCode is! int ||
        certificateSha256 is! String) {
      throw const FormatException('Invalid Android APK inspection result');
    }
    return AndroidApkInfo(
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      certificateSha256: certificateSha256,
    );
  }

  final String packageName;
  final String versionName;
  final int versionCode;
  final String certificateSha256;
}

final class AndroidUpdateBridge {
  const AndroidUpdateBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'app.biblerecite/update';

  final MethodChannel _channel;

  Future<AndroidApkInfo> inspectApk(File file) async {
    final values = await _channel.invokeMapMethod<Object?, Object?>(
      'inspectApk',
      {'path': file.path},
    );
    if (values == null) {
      throw const FormatException('Missing Android APK inspection result');
    }
    return AndroidApkInfo.fromChannelMap(values);
  }

  Future<bool> canRequestPackageInstalls() async =>
      await _channel.invokeMethod<bool>('canRequestPackageInstalls') ?? false;

  Future<void> openInstallPermission() =>
      _channel.invokeMethod<void>('openInstallPermission');

  Future<void> installApk(File file) =>
      _channel.invokeMethod<void>('installApk', {'path': file.path});

  Future<String> networkTransport() async =>
      await _channel.invokeMethod<String>('networkTransport') ?? 'none';
}

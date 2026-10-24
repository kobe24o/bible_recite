import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppRuntimePlatform { android, ios, macos, windows, other }

final appRuntimePlatformProvider = Provider<AppRuntimePlatform>(
  (ref) => detectRuntimePlatform(),
);

AppRuntimePlatform detectRuntimePlatform({
  bool? isAndroid,
  bool? isIOS,
  bool? isMacOS,
  bool? isWindows,
}) {
  if (isAndroid ?? Platform.isAndroid) return AppRuntimePlatform.android;
  if (isIOS ?? Platform.isIOS) return AppRuntimePlatform.ios;
  if (isMacOS ?? Platform.isMacOS) return AppRuntimePlatform.macos;
  if (isWindows ?? Platform.isWindows) return AppRuntimePlatform.windows;
  return AppRuntimePlatform.other;
}

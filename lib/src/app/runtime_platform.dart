import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppRuntimePlatform { android, ios, other }

final appRuntimePlatformProvider = Provider<AppRuntimePlatform>(
  (ref) => detectRuntimePlatform(),
);

AppRuntimePlatform detectRuntimePlatform({bool? isAndroid, bool? isIOS}) {
  if (isAndroid ?? Platform.isAndroid) return AppRuntimePlatform.android;
  if (isIOS ?? Platform.isIOS) return AppRuntimePlatform.ios;
  return AppRuntimePlatform.other;
}

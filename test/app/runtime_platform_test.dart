import 'package:bible_recite/src/app/runtime_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports iOS when the iOS platform flag is set', () {
    expect(
      detectRuntimePlatform(isAndroid: false, isIOS: true),
      AppRuntimePlatform.ios,
    );
  });

  test('reports Android before every other platform flag', () {
    expect(
      detectRuntimePlatform(isAndroid: true, isIOS: true),
      AppRuntimePlatform.android,
    );
  });
  test('detects macOS and Windows as supported desktop platforms', () {
    expect(
      detectRuntimePlatform(
        isAndroid: false,
        isIOS: false,
        isMacOS: true,
        isWindows: false,
      ),
      AppRuntimePlatform.macos,
    );
    expect(
      detectRuntimePlatform(
        isAndroid: false,
        isIOS: false,
        isMacOS: false,
        isWindows: true,
      ),
      AppRuntimePlatform.windows,
    );
    expect(
      detectRuntimePlatform(
        isAndroid: false,
        isIOS: false,
        isMacOS: false,
        isWindows: false,
      ),
      AppRuntimePlatform.other,
    );
  });
}

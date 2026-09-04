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
}

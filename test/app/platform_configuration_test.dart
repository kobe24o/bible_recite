import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest allows routing audio through bluetooth headsets', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.MODIFY_AUDIO_SETTINGS'));
  });

  test('release identity changes when launcher artwork changes', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(manifest, contains('@mipmap/ic_launcher_bible'));
    expect(pubspec, contains('version: 1.0.2+3'));
  });
}

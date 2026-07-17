import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest allows routing audio through bluetooth headsets', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.MODIFY_AUDIO_SETTINGS'));
  });

  test('release Android manifest allows cloud plan downloads', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('release identity changes when launcher artwork changes', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(manifest, contains('@mipmap/ic_launcher_bible'));
    expect(pubspec, contains('version: 1.0.3+4'));
  });

  test('cloud release builds use a persistent signing keystore', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final workflow = File(
      '.github/workflows/android-apk.yml',
    ).readAsStringSync();

    expect(gradle, contains('ANDROID_KEYSTORE_PATH'));
    expect(gradle, contains('ANDROID_KEYSTORE_PASSWORD'));
    expect(gradle, contains('ANDROID_KEY_ALIAS'));
    expect(gradle, contains('ANDROID_KEY_PASSWORD'));
    expect(gradle, contains('GradleException'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(workflow, contains('secrets.ANDROID_KEYSTORE_BASE64'));
  });

  test('cloud builds publish Android and iOS artifacts after validation', () {
    final workflow = File(
      '.github/workflows/android-apk.yml',
    ).readAsStringSync();

    expect(workflow, contains('flutter build apk --release'));
    expect(workflow, contains('flutter build ios --release --no-codesign'));
    expect(workflow, contains('apksigner verify --print-certs'));
    expect(workflow, contains('gh release create'));
  });
}

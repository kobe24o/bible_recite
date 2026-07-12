import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readIfExists(String path) {
  final file = File(path);
  return file.existsSync() ? file.readAsStringSync() : '';
}

void main() {
  test('uses the approved Android identity and minimum SDK', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/app/biblerecite/MainActivity.kt',
    );

    expect(gradle, contains('namespace = "app.biblerecite"'));
    expect(gradle, contains('applicationId = "app.biblerecite"'));
    expect(gradle, contains('minSdk = 24'));
    expect(activity.existsSync(), isTrue);
    expect(activity.readAsStringSync(), contains('package app.biblerecite'));
  });

  test('uses the approved Apple identities and deployment targets', () {
    final iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final macosProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final macosInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();

    expect(
      iosProject,
      contains('PRODUCT_BUNDLE_IDENTIFIER = app.biblerecite;'),
    );
    expect(iosProject, contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0;'));
    expect(macosInfo, contains('PRODUCT_BUNDLE_IDENTIFIER = app.biblerecite'));
    expect(macosProject, contains('MACOSX_DEPLOYMENT_TARGET = 10.15;'));
  });

  test('uses the approved user-visible platform names', () {
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final androidEnglish = readIfExists(
      'android/app/src/main/res/values/strings.xml',
    );
    final androidSimplifiedChinese = readIfExists(
      'android/app/src/main/res/values-zh-rCN/strings.xml',
    );
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final macosInfo = File('macos/Runner/Info.plist').readAsStringSync();
    final windowsResources = File(
      'windows/runner/Runner.rc',
    ).readAsStringSync();

    expect(androidManifest, contains('android:label="@string/app_name"'));
    expect(androidEnglish, contains('>Scripture Recite<'));
    expect(androidSimplifiedChinese, contains('>圣经背诵<'));
    expect(iosInfo, contains('<string>Scripture Recite</string>'));
    expect(macosInfo, contains('<string>Scripture Recite</string>'));
    expect(windowsResources, contains('"ProductName", "Scripture Recite"'));
  });
}

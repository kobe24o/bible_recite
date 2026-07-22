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
    expect(manifest, contains('android.permission.ACCESS_NETWORK_STATE'));
  });

  test('Android update installation uses a private FileProvider path', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final paths = File(
      'android/app/src/main/res/xml/update_file_paths.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.REQUEST_INSTALL_PACKAGES'));

    final providerElements = RegExp(r'<provider\b([^>]*)>([\s\S]*?)</provider>')
        .allMatches(manifest)
        .where((element) {
          return _attributes(element.group(1)!)['name'] ==
              'androidx.core.content.FileProvider';
        })
        .toList();
    expect(providerElements, hasLength(1));
    final provider = providerElements.single;
    expect(_attributes(provider.group(1)!), {
      'name': 'androidx.core.content.FileProvider',
      'authorities': r'${applicationId}.update-files',
      'exported': 'false',
      'grantUriPermissions': 'true',
    });

    final metadata = RegExp(r'<meta-data\b([^>]*)/>')
        .allMatches(provider.group(2)!)
        .map((element) => _attributes(element.group(1)!))
        .toList();
    expect(metadata, hasLength(1));
    expect(metadata.single['name'], 'android.support.FILE_PROVIDER_PATHS');
    expect(metadata.single['resource'], '@xml/update_file_paths');

    final allowedRoots = RegExp(r'<(?!/|\?)([a-z-]+)\b([^>]*)>')
        .allMatches(paths)
        .where((element) => element.group(1) != 'paths')
        .toList();
    expect(allowedRoots, hasLength(1));
    expect(allowedRoots.single.group(1), 'cache-path');
    expect(_plainAttributes(allowedRoots.single.group(2)!), {
      'name': 'updates',
      'path': 'updates/',
    });
  });

  test(
    'Android update channel stays on the system-confirmed installer path',
    () {
      final source = File(
        'android/app/src/main/kotlin/app/biblerecite/AppUpdateChannel.kt',
      ).readAsStringSync();

      expect(source, contains('Build.VERSION.SDK_INT >= 28'));
      expect(source, contains('PackageManager.GET_SIGNING_CERTIFICATES'));
      expect(source, contains('PackageManager.GET_SIGNATURES'));
      expect(
        source,
        contains('packageInfo.signingInfo?.apkContentsSigners?.singleOrNull()'),
      );
      expect(source, contains('packageInfo.signatures?.singleOrNull()'));
      expect(source, contains('Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES'));
      expect(source, contains(r'Uri.parse("package:${activity.packageName}")'));
      expect(source, contains('Intent.ACTION_INSTALL_PACKAGE'));
      expect(source, contains('Intent.FLAG_GRANT_READ_URI_PERMISSION'));
      expect(source, contains('apk.parentFile != updateDirectory'));
    },
  );

  test('release identity changes when launcher artwork changes', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(manifest, contains('@mipmap/ic_launcher_bible'));
    expect(pubspec, contains('version: 1.0.3+4'));
  });

  test('phonetic recitation scoring packages its pinned pinyin dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('lpinyin: 2.0.3'));
    expect(
      pubspec,
      contains('assets/pronunciation/bible_pinyin_overrides.json'),
    );
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
    expect(workflow, contains('flutter build ios --simulator --debug'));
    expect(workflow, contains('apksigner verify --print-certs'));
    expect(workflow, contains(r'print tolower($NF)'));
    expect(workflow, contains('gh release create'));
    expect(workflow, contains('--latest'));
  });
}

Map<String, String> _attributes(String source) => {
  for (final match in RegExp(r'android:([\w]+)="([^"]*)"').allMatches(source))
    match.group(1)!: match.group(2)!,
};

Map<String, String> _plainAttributes(String source) => {
  for (final match in RegExp(r'([\w-]+)="([^"]*)"').allMatches(source))
    match.group(1)!: match.group(2)!,
};

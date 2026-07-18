import 'dart:convert';

import 'package:bible_recite/src/features/update/data/update_verifier.dart';
import 'package:bible_recite/src/features/update/domain/app_version.dart';
import 'package:bible_recite/src/features/update/domain/update_manifest.dart';
import 'package:bible_recite/src/features/update/platform/android_update_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const _certificateSha256 =
    '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7';

void main() {
  final manifest = UpdateManifest.fromPayloadBytes(
    utf8.encode(
      jsonEncode({
        'versionName': '1.0.5',
        'buildNumber': '6',
        'sourceCommit': '0123456789abcdef',
        'publishedAt': '2026-07-18T12:00:00Z',
        'releaseNotes': 'Improved update delivery.',
        'releasePageUrl':
            'https://github.com/kobe24o/bible_recite/releases/tag/v1.0.5',
        'android': {
          'packageName': 'app.biblerecite',
          'fileName': 'BibleRecite-1.0.5+6.apk',
          'size': 123456,
          'sha256': 'a' * 64,
          'signingCertificateSha256': _certificateSha256,
          'urls': ['https://downloads.example.com/BibleRecite-1.0.5+6.apk'],
        },
      }),
    ),
  );

  test(
    'accepts only a newer APK matching the signed Android manifest',
    () async {
      await UpdateVerifier().verifyAndroidPackage(
        apk: const AndroidApkInfo(
          packageName: 'app.biblerecite',
          versionName: '1.0.5',
          versionCode: 6,
          certificateSha256: _certificateSha256,
        ),
        manifest: manifest,
        installedVersion: AppVersion.parse('1.0.4', '5'),
      );
    },
  );

  test('rejects APK metadata that does not match the signed manifest', () async {
    final verifier = UpdateVerifier();
    final installedVersion = AppVersion.parse('1.0.4', '5');

    for (final apk in [
      const AndroidApkInfo(
        packageName: 'com.example.other',
        versionName: '1.0.5',
        versionCode: 6,
        certificateSha256: _certificateSha256,
      ),
      const AndroidApkInfo(
        packageName: 'app.biblerecite',
        versionName: '1.0.6',
        versionCode: 6,
        certificateSha256: _certificateSha256,
      ),
      const AndroidApkInfo(
        packageName: 'app.biblerecite',
        versionName: '1.0.05',
        versionCode: 6,
        certificateSha256: _certificateSha256,
      ),
      const AndroidApkInfo(
        packageName: 'app.biblerecite',
        versionName: '1.0.5',
        versionCode: 7,
        certificateSha256: _certificateSha256,
      ),
      const AndroidApkInfo(
        packageName: 'app.biblerecite',
        versionName: '1.0.5',
        versionCode: 6,
        certificateSha256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    ]) {
      await expectLater(
        verifier.verifyAndroidPackage(
          apk: apk,
          manifest: manifest,
          installedVersion: installedVersion,
        ),
        throwsA(isA<UpdateVerificationException>()),
      );
    }
  });

  test('rejects an APK when the signed remote version is not newer', () async {
    await expectLater(
      UpdateVerifier().verifyAndroidPackage(
        apk: const AndroidApkInfo(
          packageName: 'app.biblerecite',
          versionName: '1.0.5',
          versionCode: 6,
          certificateSha256: _certificateSha256,
        ),
        manifest: manifest,
        installedVersion: AppVersion.parse('1.0.5', '6'),
      ),
      throwsA(
        isA<UpdateVerificationException>().having(
          (error) => error.reason,
          'reason',
          'not_newer',
        ),
      ),
    );
  });
}

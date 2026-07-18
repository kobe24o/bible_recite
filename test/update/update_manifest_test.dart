import 'dart:convert';

import 'package:bible_recite/src/features/update/domain/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _certificateSha256 =
    '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7';

void main() {
  final payload = _validPayload();
  final payloadBytes = utf8.encode(jsonEncode(payload));

  test('decodes a protocol-one envelope and its Android update manifest', () {
    final envelope = SignedUpdateEnvelope.decode(
      utf8.encode(
        jsonEncode({
          'protocol': 1,
          'payload': base64Encode(payloadBytes),
          'signature': base64Encode(List<int>.filled(64, 1)),
        }),
      ),
    );

    expect(envelope.protocol, 1);
    expect(envelope.payloadBytes, payloadBytes);
    expect(envelope.signatureBytes, List<int>.filled(64, 1));

    final manifest = UpdateManifest.fromPayloadBytes(envelope.payloadBytes);
    expect(manifest.version.major, 1);
    expect(manifest.version.minor, 0);
    expect(manifest.version.patch, 5);
    expect(manifest.version.buildNumber, 6);
    expect(manifest.sourceCommit, '0123456789abcdef');
    expect(
      manifest.releasePageUrl.toString(),
      'https://github.com/kobe24o/bible_recite/releases/tag/v1.0.5',
    );
    expect(manifest.android.packageName, 'app.biblerecite');
    expect(manifest.android.fileName, 'BibleRecite-1.0.5+6.apk');
    expect(manifest.android.size, 123456);
    expect(manifest.android.sha256, 'a' * 64);
    expect(manifest.android.signingCertificateSha256, _certificateSha256);
    expect(manifest.android.urls, [
      Uri.parse('https://downloads.example.com/BibleRecite-1.0.5+6.apk'),
      Uri.parse(
        'https://github.com/kobe24o/bible_recite/releases/download/v1.0.5/BibleRecite-1.0.5+6.apk',
      ),
    ]);
  });

  test('rejects malformed signed envelopes', () {
    expect(
      () => SignedUpdateEnvelope.decode(
        utf8.encode(jsonEncode({'protocol': 1, 'payload': 'e30='})),
      ),
      throwsFormatException,
    );
    expect(
      () => SignedUpdateEnvelope.decode(
        utf8.encode(
          jsonEncode({
            'protocol': 2,
            'payload': base64Encode(payloadBytes),
            'signature': base64Encode(List<int>.filled(64, 1)),
          }),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => SignedUpdateEnvelope.decode(
        utf8.encode(
          jsonEncode({
            'protocol': 1,
            'payload': base64Encode(payloadBytes),
            'signature': 'not base64',
          }),
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed Android update assets', () {
    for (final invalidPayload in [
      _withAndroidField('packageName', 'com.example.other'),
      _withAndroidField('fileName', 'update.apk'),
      _withAndroidField('size', -1),
      _withAndroidField('sha256', 'A' * 64),
      _withAndroidField('signingCertificateSha256', 'b' * 64),
      _withAndroidField('urls', [
        'https://one.example.com/update.apk',
        'https://two.example.com/update.apk',
        'https://three.example.com/update.apk',
      ]),
      _withAndroidField('urls', ['http://downloads.example.com/update.apk']),
    ]) {
      expect(
        () => UpdateManifest.fromPayloadBytes(
          utf8.encode(jsonEncode(invalidPayload)),
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects missing and malformed required manifest fields', () {
    final missingVersion = Map<String, Object?>.from(payload)
      ..remove('versionName');
    final httpReleasePage = Map<String, Object?>.from(payload)
      ..['releasePageUrl'] = 'http://github.com/kobe24o/bible_recite/releases';

    for (final invalidPayload in [missingVersion, httpReleasePage]) {
      expect(
        () => UpdateManifest.fromPayloadBytes(
          utf8.encode(jsonEncode(invalidPayload)),
        ),
        throwsFormatException,
      );
    }
  });
}

Map<String, Object?> _validPayload() => {
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
    'urls': [
      'https://downloads.example.com/BibleRecite-1.0.5+6.apk',
      'https://github.com/kobe24o/bible_recite/releases/download/v1.0.5/BibleRecite-1.0.5+6.apk',
    ],
  },
};

Map<String, Object?> _withAndroidField(String field, Object? value) {
  final result = _validPayload();
  final android = Map<String, Object?>.from(result['android']! as Map);
  android[field] = value;
  result['android'] = android;
  return result;
}

import 'dart:convert';

import 'package:bible_recite/src/features/update/data/update_feed_client.dart';
import 'package:bible_recite/src/features/update/data/update_signing_public_key.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

const _certificateSha256 =
    '4066fe3c0e57ec575e5d37b741d68d347f8af80b7cf9da4799636d7039b5a7e7';

void main() {
  final algorithm = Ed25519();
  final primary = Uri.parse('https://updates.example.com/latest.json');
  final secondary = Uri.parse('https://backup.example.com/latest.json');

  late SimpleKeyPair keyPair;
  late SimplePublicKey publicKey;

  setUpAll(() async {
    keyPair = await algorithm.newKeyPairFromSeed(
      List<int>.generate(32, (index) => index),
    );
    publicKey = await keyPair.extractPublicKey();
  });

  test('configures a 32-byte Ed25519 public key for signed update feeds', () {
    expect(updateSigningPublicKey.type, KeyPairType.ed25519);
    expect(updateSigningPublicKey.bytes, hasLength(32));
  });

  test('builds an HTTPS R2 feed source before the approved fallbacks', () {
    final sources = buildUpdateFeedSources(
      r2PublicBaseUrl: Uri.parse('https://updates.example.com/releases'),
    );

    expect(sources, [
      Uri.parse('https://updates.example.com/releases/updates/latest.json'),
      Uri.parse(
        'https://raw.githubusercontent.com/kobe24o/bible_recite/update-feed/updates/latest.json',
      ),
      Uri.parse(
        'https://fastly.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
      ),
      Uri.parse(
        'https://cdn.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
      ),
      Uri.parse(
        'https://gcore.jsdelivr.net/gh/kobe24o/bible_recite@update-feed/updates/latest.json',
      ),
    ]);
    expect(
      () => sources.add(Uri.parse('https://untrusted.example.com/latest.json')),
      throwsUnsupportedError,
    );
  });

  test('uses approved CDN and GitHub fallbacks without an R2 URL', () {
    final sources = buildUpdateFeedSources();

    expect(sources.first.host, 'raw.githubusercontent.com');
    expect(sources, hasLength(4));
  });

  test('rejects an R2 public base URL that is not HTTPS', () {
    expect(
      () => buildUpdateFeedSources(
        r2PublicBaseUrl: Uri.parse('http://updates.example.com'),
      ),
      throwsArgumentError,
    );
  });

  test('returns the manifest from a valid primary signed feed', () async {
    final feed = await _signedFeed(algorithm, keyPair, versionName: '1.0.5');
    final transport = _FakeTransport({primary: feed});
    final client = UpdateFeedClient(
      sources: [primary, secondary],
      transport: transport,
      publicKey: publicKey,
    );

    final manifest = await client.fetchLatest();

    expect(manifest.version.major, 1);
    expect(manifest.version.minor, 0);
    expect(manifest.version.patch, 5);
    expect(manifest.version.buildNumber, 6);
    expect(transport.requests, [primary, secondary]);
  });

  test('uses the secondary feed after the primary transport throws', () async {
    final feed = await _signedFeed(algorithm, keyPair);
    final transport = _FakeTransport({
      primary: StateError('network unavailable'),
      secondary: feed,
    });
    final client = UpdateFeedClient(
      sources: [primary, secondary],
      transport: transport,
      publicKey: publicKey,
    );

    final manifest = await client.fetchLatest();

    expect(manifest.version.major, 1);
    expect(manifest.version.minor, 0);
    expect(manifest.version.patch, 5);
    expect(manifest.version.buildNumber, 6);
    expect(transport.requests, [primary, secondary]);
  });

  test(
    'chooses the newest verified manifest when a CDN serves a stale one',
    () async {
      final stale = await _signedFeed(algorithm, keyPair, versionName: '1.0.6');
      final latest = await _signedFeed(
        algorithm,
        keyPair,
        versionName: '1.0.10',
      );
      final transport = _FakeTransport({primary: stale, secondary: latest});
      final client = UpdateFeedClient(
        sources: [primary, secondary],
        transport: transport,
        publicKey: publicKey,
      );

      final manifest = await client.fetchLatest();

      expect(manifest.version.patch, 10);
      expect(transport.requests, [primary, secondary]);
    },
  );

  test(
    'reports every source failure when no signed feed can be used',
    () async {
      final transport = _FakeTransport({
        primary: StateError('network unavailable'),
        secondary: const FormatException('malformed response'),
      });
      final client = UpdateFeedClient(
        sources: [primary, secondary],
        transport: transport,
        publicKey: publicKey,
      );

      await expectLater(
        client.fetchLatest(),
        throwsA(
          isA<UpdateFeedException>()
              .having((error) => error.failures, 'failures', hasLength(2))
              .having(
                (error) => error.failures.first,
                'primary failure',
                contains('updates.example.com'),
              )
              .having(
                (error) => error.failures.last,
                'secondary failure',
                contains('backup.example.com'),
              ),
        ),
      );
    },
  );

  test(
    'rejects a feed whose signature does not match its raw payload bytes',
    () async {
      final feed = await _signedFeed(
        algorithm,
        keyPair,
        signature: List.filled(64, 0),
      );
      final client = UpdateFeedClient(
        sources: [primary],
        transport: _FakeTransport({primary: feed}),
        publicKey: publicKey,
      );

      await expectLater(
        client.fetchLatest(),
        throwsA(
          isA<UpdateFeedException>().having(
            (error) => error.failures.single,
            'signature failure',
            contains('Invalid update signature'),
          ),
        ),
      );
    },
  );

  test('parses the payload only after accepting its signed envelope', () async {
    final feed = await _signedFeed(
      algorithm,
      keyPair,
      releaseNotes: 'A signed payload is parsed.',
    );
    final client = UpdateFeedClient(
      sources: [primary],
      transport: _FakeTransport({primary: feed}),
      publicKey: publicKey,
    );

    final manifest = await client.fetchLatest();

    expect(manifest.releaseNotes, 'A signed payload is parsed.');
    expect(manifest.android.urls, hasLength(2));
  });
}

Future<List<int>> _signedFeed(
  Ed25519 algorithm,
  SimpleKeyPair keyPair, {
  String versionName = '1.0.5',
  String releaseNotes = 'Improved update delivery.',
  List<int>? signature,
}) async {
  final payloadBytes = utf8.encode(
    jsonEncode({
      'versionName': versionName,
      'buildNumber': '6',
      'sourceCommit': '0123456789abcdef',
      'publishedAt': '2026-07-18T12:00:00Z',
      'releaseNotes': releaseNotes,
      'releasePageUrl':
          'https://github.com/kobe24o/bible_recite/releases/tag/v$versionName',
      'android': {
        'packageName': 'app.biblerecite',
        'fileName': 'BibleRecite-$versionName+6.apk',
        'size': 123456,
        'sha256': 'a' * 64,
        'signingCertificateSha256': _certificateSha256,
        'urls': [
          'https://downloads.example.com/BibleRecite-$versionName+6.apk',
          'https://github.com/kobe24o/bible_recite/releases/download/v$versionName/BibleRecite-$versionName+6.apk',
        ],
      },
    }),
  );
  final signed = await algorithm.sign(payloadBytes, keyPair: keyPair);

  return utf8.encode(
    jsonEncode({
      'protocol': 1,
      'payload': base64Encode(payloadBytes),
      'signature': base64Encode(signature ?? signed.bytes),
    }),
  );
}

final class _FakeTransport implements UpdateBytesTransport {
  _FakeTransport(this.responses);

  final Map<Uri, Object> responses;
  final List<Uri> requests = [];

  @override
  Future<List<int>> get(Uri uri) async {
    requests.add(uri);
    final response = responses[uri];
    if (response is List<int>) {
      return response;
    }
    if (response is Object) {
      throw response;
    }
    throw StateError('No response registered for $uri');
  }
}

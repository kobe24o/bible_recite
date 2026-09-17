import 'package:bible_recite/src/features/devotion/data/devotion_feed_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'devotion_models_test.dart' show complete2026Json;

void main() {
  test('falls back to the next mirror', () async {
    final client = DevotionFeedClient(
      loader: (uri) async {
        if (uri.host == 'first.example') {
          throw const DevotionFeedException('down');
        }
        return complete2026Json;
      },
    );

    final feed = await client.fetchFirst([
      Uri.parse('https://first.example/a'),
      Uri.parse('https://next.example/a'),
    ]);

    expect(feed.revision, 1);
  });

  test('rejects insecure URLs and oversized responses', () async {
    final client = DevotionFeedClient(
      maxBytes: 20,
      loader: (_) async => 'x' * 21,
    );

    expect(
      () => client.fetch(Uri.parse('http://example.com/devotion-plans.json')),
      throwsArgumentError,
    );
    await expectLater(
      client.fetch(Uri.parse('https://example.com/devotion-plans.json')),
      throwsA(isA<DevotionFeedException>()),
    );
  });

  test(
    'falls back when an injected loader throws an ordinary exception',
    () async {
      final client = DevotionFeedClient(
        loader: (uri) async {
          if (uri.host == 'first.example') throw StateError('offline');
          return complete2026Json;
        },
      );

      final feed = await client.fetchFirst([
        Uri.parse('https://first.example/a'),
        Uri.parse('https://next.example/a'),
      ]);

      expect(feed.revision, 1);
    },
  );

  test('applies the deadline to an injected loader', () async {
    final client = DevotionFeedClient(
      timeout: const Duration(milliseconds: 10),
      loader: (_) => Future<String>.delayed(
        const Duration(milliseconds: 50),
        () => complete2026Json,
      ),
    );

    await expectLater(
      client.fetch(Uri.parse('https://example.com/devotion-plans.json')),
      throwsA(isA<DevotionFeedException>()),
    );
  });
}

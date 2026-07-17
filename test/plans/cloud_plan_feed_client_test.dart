import 'package:bible_recite/src/features/plans/data/cloud_plan_feed_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads and validates an HTTPS cloud plan feed', () async {
    final client = CloudPlanFeedClient(
      loader: (uri) async => '{"protocolVersion":1,"plans":[]}',
    );

    final manifest = await client.fetch(
      Uri.parse('https://example.com/cloud-plans.json'),
    );

    expect(manifest.protocolVersion, 1);
  });

  test('rejects insecure URLs and oversized responses', () async {
    final client = CloudPlanFeedClient(
      maxBytes: 20,
      loader: (uri) async => 'x' * 21,
    );
    expect(
      () => client.fetch(Uri.parse('http://example.com/cloud-plans.json')),
      throwsArgumentError,
    );
    expect(
      () => client.fetch(Uri.parse('https://example.com/cloud-plans.json')),
      throwsA(isA<CloudPlanFeedException>()),
    );
  });

  test('tries the next HTTPS source when a download fails', () async {
    final attempts = <Uri>[];
    final client = CloudPlanFeedClient(
      loader: (uri) async {
        attempts.add(uri);
        if (uri.host == 'raw.githubusercontent.com') {
          throw const CloudPlanFeedException('DNS lookup failed');
        }
        return '{"protocolVersion":1,"plans":[]}';
      },
    );
    final mirror = Uri.parse(
      'https://cdn.jsdelivr.net/gh/example/plans@main/cloud-plans.json',
    );
    final raw = Uri.parse(
      'https://raw.githubusercontent.com/example/plans/main/cloud-plans.json',
    );

    final manifest = await client.fetchFirst([raw, mirror]);

    expect(manifest.protocolVersion, 1);
    expect(attempts, [raw, mirror]);
  });

  test('reports every attempted host when all sources fail', () async {
    final client = CloudPlanFeedClient(
      loader: (uri) async => throw CloudPlanFeedException('${uri.host} DNS'),
    );

    await expectLater(
      client.fetchFirst([
        Uri.parse('https://gcore.jsdelivr.net/plans.json'),
        Uri.parse('https://raw.githubusercontent.com/plans.json'),
      ]),
      throwsA(
        isA<CloudPlanFeedException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('gcore.jsdelivr.net'),
            contains('raw.githubusercontent.com'),
          ),
        ),
      ),
    );
  });
}

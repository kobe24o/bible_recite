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
}

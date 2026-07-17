import 'package:bible_recite/src/features/plans/application/plan_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official source uses the CDN before the GitHub Raw fallback', () {
    expect(defaultCloudPlanSourceUrl, officialCloudPlanCdnUrl);
    expect(cloudPlanSourceCandidates(officialCloudPlanRawUrl), [
      Uri.parse(officialCloudPlanCdnUrl),
      Uri.parse(officialCloudPlanRawUrl),
    ]);
  });

  test('custom source is not replaced with an official endpoint', () {
    const source = 'https://example.com/custom-plans.json';

    expect(cloudPlanSourceCandidates(source), [Uri.parse(source)]);
  });
}

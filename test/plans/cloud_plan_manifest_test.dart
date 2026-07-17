import 'dart:io';

import 'package:bible_recite/src/features/plans/domain/cloud_plan_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the bundled two-plan manifest with exact passage counts', () {
    final manifest = CloudPlanManifest.parse(
      File('assets/cloud_plans.json').readAsStringSync(),
    );

    expect(manifest.protocolVersion, 1);
    expect(manifest.plans, hasLength(2));
    expect(manifest.plans[0].passages, hasLength(20));
    expect(manifest.plans[1].passages, hasLength(66));
    expect(
      manifest.plans[1].passages.any((p) => p.endVerse > p.startVerse),
      isTrue,
    );
  });

  test('rejects unsupported protocols and reversed ranges', () {
    expect(
      () => CloudPlanManifest.parse('{"protocolVersion":2,"plans":[]}'),
      throwsFormatException,
    );
    expect(
      () => CloudPlanManifest.parse('''{
        "protocolVersion":1,
        "plans":[{
          "id":"bad","title":"Bad","push":true,"revision":1,
          "defaultTranslationId":"cmn-cu89s",
          "passages":[{"order":1,"bookId":"JHN","startChapter":1,
          "startVerse":5,"endChapter":1,"endVerse":2}]
        }]
      }'''),
      throwsFormatException,
    );
  });
}

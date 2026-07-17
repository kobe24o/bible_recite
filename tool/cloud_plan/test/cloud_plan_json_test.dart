import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// ignore: avoid_relative_lib_imports
import '../lib/cloud_plan_json.dart';

void main() {
  test('generates a versioned manifest and preserves multi-verse ranges', () {
    final output = Directory.systemTemp.createTempSync('cloud-plan-json-');
    addTearDown(() => output.deleteSync(recursive: true));

    final summary = const CloudPlanJsonGenerator().generate(
      CloudPlanJsonRequest(
        classicMarkdownPath: 'D:/Personal/Downloads/圣经经典篇章.md',
        keyVersesMarkdownPath: 'D:/Personal/Downloads/每卷书钥节.md',
        outputPath: '',
      ),
      outputFile: File('${output.path}/cloud-plans.json'),
    );

    expect(summary.classicPassageCount, 20);
    expect(summary.keyVersePassageCount, 66);
    final json =
        jsonDecode(File('${output.path}/cloud-plans.json').readAsStringSync())
            as Map<String, Object?>;
    expect(json['protocolVersion'], 1);
    final plans = json['plans']! as List<Object?>;
    expect(plans, hasLength(2));
    expect(plans.every((item) => (item as Map)['push'] == true), isTrue);
    final keyVerses = plans[1] as Map<String, Object?>;
    final passages = keyVerses['passages']! as List<Object?>;
    expect(passages, hasLength(66));
    expect(
      passages.any(
        (item) =>
            (item as Map<String, Object?>)['endVerse'] != item['startVerse'],
      ),
      isTrue,
    );
  });
}

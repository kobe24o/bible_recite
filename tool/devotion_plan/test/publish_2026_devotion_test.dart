import 'dart:io';

import 'package:bible_recite/src/features/devotion/domain/devotion_models.dart';
import 'package:test/test.dart';

import '../bin/publish_2026_devotion.dart';

void main() {
  test('publishes the supplied schedule deterministically', () async {
    final directory = await Directory.systemTemp.createTemp('devotion-plan-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('tool/devotion_plan/data/2026-devotion-source.txt');
    final output = File('${directory.path}/devotion-plans.json');

    await publish2026Devotion(input: source, output: output, revision: 1);

    final feed = DevotionManifest.parse(await output.readAsString());
    expect(feed.years.single.days, hasLength(365));
    expect(feed.dayFor(DateTime(2026, 1, 1))!.passages.single.bookId, 'EZR');
    expect(feed.dayFor(DateTime(2026, 12, 31))!.passages.single.endChapter, 52);

    final firstOutput = await output.readAsString();
    await publish2026Devotion(input: source, output: output, revision: 1);
    expect(await output.readAsString(), firstOutput);
  });
}

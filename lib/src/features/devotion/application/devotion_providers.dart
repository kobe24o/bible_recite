import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devotion_feed_client.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../domain/devotion_models.dart';

const officialDevotionGcoreUrl =
    'https://gcore.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/devotion-plans.json';
const officialDevotionFastlyUrl =
    'https://fastly.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/devotion-plans.json';
const officialDevotionCdnUrl =
    'https://cdn.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/devotion-plans.json';
const officialDevotionRawUrl =
    'https://raw.githubusercontent.com/kobe24o/bible-recite-plans/main/devotion-plans.json';

const defaultDevotionSourceUrl = officialDevotionGcoreUrl;
const devotionManifestSettingKey = devotionCachedManifestSettingKey;

List<Uri> devotionSourceCandidates(String source) {
  const officialSources = {
    officialDevotionGcoreUrl,
    officialDevotionFastlyUrl,
    officialDevotionCdnUrl,
    officialDevotionRawUrl,
  };
  if (officialSources.contains(source)) {
    return [
      Uri.parse(officialDevotionGcoreUrl),
      Uri.parse(officialDevotionFastlyUrl),
      Uri.parse(officialDevotionCdnUrl),
      Uri.parse(officialDevotionRawUrl),
    ];
  }
  return [Uri.parse(source)];
}

final devotionFeedClientProvider = Provider<DevotionFeedClient>(
  (ref) => DevotionFeedClient(),
);

/// Downloads the current schedule, persists it, then lets the caller refresh
/// UI state. The callback runs only after a validated cache write succeeds.
Future<DevotionManifest> syncDevotionManifest({
  required SqlitePlanRepository repository,
  required DevotionFeedClient client,
  FutureOr<void> Function()? onCached,
}) async {
  final source = await repository.getSetting(
    'devotion_source_url',
    defaultDevotionSourceUrl,
  );
  final manifest = await client.fetchFirst(devotionSourceCandidates(source));
  await repository.cacheDevotionManifest(_encodeManifest(manifest));
  await onCached?.call();
  return manifest;
}

String _encodeManifest(DevotionManifest manifest) => jsonEncode({
  'format': 'bible-recite-devotion-plans',
  'version': 1,
  'revision': manifest.revision,
  'years': [
    for (final year in manifest.years)
      {
        'year': year.year,
        'days': [
          for (final day in year.days)
            {
              'date': day.date.toIso8601String().substring(0, 10),
              'passages': [
                for (final passage in day.passages) passage.toJson(),
              ],
            },
        ],
      },
  ],
});

final devotionRevisionProvider = NotifierProvider<DevotionRevision, int>(
  DevotionRevision.new,
);

final class DevotionRevision extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;
}

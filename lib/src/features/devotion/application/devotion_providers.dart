import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devotion_feed_client.dart';

const officialDevotionGcoreUrl =
    'https://gcore.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/devotion-plans.json';
const officialDevotionFastlyUrl =
    'https://fastly.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/devotion-plans.json';
const officialDevotionCdnUrl =
    'https://cdn.jsdelivr.net/gh/kobe24o/bible-recite-plans@main/devotion-plans.json';
const officialDevotionRawUrl =
    'https://raw.githubusercontent.com/kobe24o/bible-recite-plans/main/devotion-plans.json';

const defaultDevotionSourceUrl = officialDevotionGcoreUrl;

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

final devotionRevisionProvider = NotifierProvider<DevotionRevision, int>(
  DevotionRevision.new,
);

final class DevotionRevision extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;
}

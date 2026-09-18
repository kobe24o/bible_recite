import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/devotion_feed_client.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../plans/application/plan_providers.dart';
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

typedef DevotionClock = DateTime Function();

/// An injectable clock keeps calendar-day behavior deterministic in tests.
final devotionClockProvider = Provider<DevotionClock>((ref) => DateTime.now);

/// The current local calendar day for devotion lookup.
///
/// The app refreshes this provider when it resumes and at the next midnight;
/// consumers therefore do not retain a startup timestamp across a day change.
final devotionTodayProvider = NotifierProvider<DevotionToday, DateTime>(
  DevotionToday.new,
);

final class DevotionToday extends Notifier<DateTime> {
  @override
  DateTime build() => _calendarDay(ref.watch(devotionClockProvider)());

  void refresh() {
    state = _calendarDay(ref.read(devotionClockProvider)());
  }
}

DateTime _calendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

final cachedDevotionManifestProvider = FutureProvider<DevotionManifest?>((
  ref,
) async {
  ref.watch(devotionRevisionProvider);
  final repository = await ref.watch(planRepositoryProvider.future);
  return repository.loadCachedDevotionManifest();
});

final devotionSyncProvider = NotifierProvider<DevotionSync, AsyncValue<void>>(
  DevotionSync.new,
);

final class DevotionSync extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> sync() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await syncDevotionManifest(
        repository: await ref.read(planRepositoryProvider.future),
        client: ref.read(devotionFeedClientProvider),
        onCached: () => ref.read(devotionRevisionProvider.notifier).refresh(),
      );
    });
  }
}

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
  final response = await client.fetchFirstWithSource(
    devotionSourceCandidates(source),
  );
  await repository.cacheDevotionManifest(response.source);
  await onCached?.call();
  return response.manifest;
}

final devotionRevisionProvider = NotifierProvider<DevotionRevision, int>(
  DevotionRevision.new,
);

final class DevotionRevision extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state++;
}

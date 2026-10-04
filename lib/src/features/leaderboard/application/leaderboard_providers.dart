import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../devotion/application/devotion_providers.dart';
import '../data/device_alias_source.dart';
import '../data/leaderboard_config.dart';
import '../data/offline_leaderboard_gateway.dart';
import '../data/supabase_leaderboard_gateway.dart';
import '../domain/leaderboard_gateway.dart';
import '../domain/leaderboard_models.dart';
import 'leaderboard_snapshot_builder.dart';
import 'leaderboard_sync_controller.dart';

final leaderboardConfigProvider = Provider(
  (ref) => const LeaderboardConfig.fromEnvironment(),
);
final leaderboardGatewayProvider = FutureProvider<LeaderboardGateway>((
  ref,
) async {
  final config = ref.watch(leaderboardConfigProvider);
  if (!config.isConfigured) return OfflineLeaderboardGateway();
  // Initialization is lazy; blank configuration creates no SDK client or network.
  await Supabase.initialize(
    url: config.url.trim(),
    publishableKey: config.publishableKey.trim(),
  );
  return SupabaseLeaderboardGateway(
    SupabaseLeaderboardTransport(Supabase.instance.client),
  );
});
Future<LeaderboardSnapshot> loadLeaderboardSnapshot(
  SqlitePlanRepository repository,
) async {
  await repository.evaluateAndUnlockAchievements(source: 'backfill');
  return buildLeaderboardSnapshot(
    recitation: await repository.getRecitationSummary(),
    learning: await repository.getLearningStats(),
    devotion: await repository.getDevotionStats(DateTime.now()),
    quiz: await repository.getQuizSummary(),
    achievements: await repository.listAchievementProgress(),
    totalBadgeAwards: await repository.getLeaderboardAwardCount(),
  );
}

final leaderboardSnapshotProvider = FutureProvider<LeaderboardSnapshot>((
  ref,
) async {
  ref.watch(recitationDataRevisionProvider);
  ref.watch(presetPlanRevisionProvider);
  ref.watch(devotionRevisionProvider);
  return loadLeaderboardSnapshot(
    await ref.watch(planRepositoryProvider.future),
  );
});
final leaderboardSyncControllerProvider =
    FutureProvider<LeaderboardSyncController>((ref) async {
      final repository = await ref.watch(planRepositoryProvider.future);
      LeaderboardGateway gateway;
      try {
        gateway = await ref.watch(leaderboardGatewayProvider.future);
      } catch (_) {
        gateway = OfflineLeaderboardGateway();
      }
      final source = DeviceAliasSource();
      return LeaderboardSyncController(
        repository: repository,
        gateway: gateway,
        snapshotLoader: () => loadLeaderboardSnapshot(repository),
        identityLoader: () async {
          final fallback = await source.loadOrCreate(repository);
          final name = (await repository.getSetting('profile_name', '')).trim();
          return LeaderboardIdentity(
            displayName: String.fromCharCodes(
              (name.isEmpty ? fallback : name).runes.take(80),
            ),
            installationAlias: await repository.getSetting(
              'leaderboard_install_alias',
              '',
            ),
          );
        },
      );
    });
final leaderboardLastSyncProvider = FutureProvider<DateTime?>((ref) async {
  ref.watch(recitationDataRevisionProvider);
  final repository = await ref.watch(planRepositoryProvider.future);
  return DateTime.tryParse(
    await repository.getSetting('leaderboard_last_success', ''),
  );
});

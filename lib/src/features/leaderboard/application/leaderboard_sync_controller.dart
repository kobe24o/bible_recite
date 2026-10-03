import 'dart:convert';
import '../../plans/data/sqlite_plan_repository.dart';
import '../data/leaderboard_codec.dart';
import '../domain/leaderboard_gateway.dart';
import '../domain/leaderboard_models.dart';

final class LeaderboardSyncController {
  LeaderboardSyncController({
    required this.repository,
    required this.gateway,
    required this.snapshotLoader,
    required this.identityLoader,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final SqlitePlanRepository repository;
  final LeaderboardGateway gateway;
  final Future<LeaderboardSnapshot> Function() snapshotLoader;
  final Future<LeaderboardIdentity> Function() identityLoader;
  final DateTime Function() clock;
  Future<bool>? _syncing;
  bool _syncFailed = false;
  final _reads = <LeaderboardMetric, Future<LeaderboardViewData>>{};
  static const uploadInterval = Duration(minutes: 15);
  static const cacheInterval = Duration(minutes: 5);

  Future<void> markDirty() => repository.markLeaderboardDirty(at: clock());
  Future<bool> isDirty() async =>
      (await repository.getSetting('leaderboard_dirty_since', '')).isNotEmpty;

  /// Day streaks can change without a write. Rebuild on launch/resume/day rollover.
  Future<void> onResume() async {
    final now = clock();
    final day = '${now.year}-${now.month}-${now.day}';
    if (await repository.getSetting('leaderboard_day', '') != day) {
      await repository.markLeaderboardDirty(at: now.subtract(uploadInterval));
      await repository.setSetting('leaderboard_day', day);
    }
    await syncIfDue();
  }

  Future<bool> syncIfDue({bool force = false}) async {
    if ((gateway is LeaderboardAvailability &&
        !(gateway as LeaderboardAvailability).isAvailable)) {
      return false;
    }
    final pending = _syncing;
    if (pending != null) return pending;
    final request = _sync(force);
    _syncing = request;
    try {
      return await request;
    } finally {
      _syncing = null;
    }
  }

  Future<bool> _sync(bool force) async {
    try {
      final now = clock();
      final dirty = DateTime.tryParse(
        await repository.getSetting('leaderboard_dirty_since', ''),
      );
      final last = DateTime.tryParse(
        await repository.getSetting('leaderboard_last_success', ''),
      );
      if (!force &&
          (dirty == null ||
              now.difference(dirty) < uploadInterval ||
              (last != null && now.difference(last) < uploadInterval))) {
        return false;
      }
      final revision = await repository.getSetting(
        'leaderboard_dirty_version',
        '0',
      );
      await gateway.ensureIdentity(await identityLoader());
      await gateway.submitSnapshot(await snapshotLoader());
      await repository.setSetting(
        'leaderboard_last_success',
        clock().toUtc().toIso8601String(),
      );
      repository.clearLeaderboardDirtyIfVersion(revision);
      _syncFailed = false;
      return true;
    } catch (_) {
      _syncFailed = true;
      return false;
    }
  }

  Future<LeaderboardViewData?> readCached(LeaderboardMetric metric) async {
    try {
      final raw = await repository.getSetting(
        'leaderboard_cache_${metric.wireName}',
        '',
      );
      if (raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return decodeLeaderboard(
        metric,
        Map<String, dynamic>.from(json['data'] as Map),
        fromCache: true,
        unavailable:
            (gateway is LeaderboardAvailability &&
            !(gateway as LeaderboardAvailability).isAvailable),
      );
    } catch (_) {
      return null;
    }
  }

  Future<LeaderboardViewData> refresh(
    LeaderboardMetric metric, {
    bool force = false,
  }) async {
    final pending = _reads[metric];
    if (pending != null) return pending;
    final request = _refresh(metric, force);
    _reads[metric] = request;
    try {
      return await request;
    } finally {
      _reads.remove(metric);
    }
  }

  Future<LeaderboardViewData> _refresh(
    LeaderboardMetric metric,
    bool force,
  ) async {
    final cached = await readCached(metric);
    if (cached != null && !force) {
      try {
        final raw =
            jsonDecode(
                  await repository.getSetting(
                    'leaderboard_cache_${metric.wireName}',
                    '',
                  ),
                )
                as Map;
        final age = clock().difference(
          DateTime.parse(raw['cached_at'] as String),
        );
        if (!age.isNegative && age < cacheInterval) return cached;
      } catch (_) {
        /* Corrupt timestamp means refresh. */
      }
    }
    await syncIfDue(force: force);
    try {
      await gateway.ensureIdentity(await identityLoader());
      final data = await gateway.loadLeaderboard(metric);
      if (data.isUnavailable) return _unavailable(metric, cached);
      await repository.setSetting(
        'leaderboard_cache_${metric.wireName}',
        jsonEncode({
          'cached_at': clock().toUtc().toIso8601String(),
          'data': encodeLeaderboard(data),
        }),
      );
      return LeaderboardViewData(
        metric: metric,
        entries: data.entries,
        currentUser: data.currentUser,
        updatedAt: data.updatedAt,
        isUnavailable: _syncFailed,
      );
    } catch (_) {
      return _unavailable(metric, cached);
    }
  }

  LeaderboardViewData _unavailable(
    LeaderboardMetric metric,
    LeaderboardViewData? cached,
  ) => LeaderboardViewData(
    metric: metric,
    entries: cached?.entries ?? const [],
    currentUser: cached?.currentUser,
    updatedAt: cached?.updatedAt ?? clock(),
    isFromCache: cached != null,
    isUnavailable: true,
  );
}

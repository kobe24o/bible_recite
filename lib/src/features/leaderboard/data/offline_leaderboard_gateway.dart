import '../domain/leaderboard_gateway.dart';
import '../domain/leaderboard_models.dart';

final class OfflineLeaderboardGateway
    implements LeaderboardGateway, LeaderboardAvailability {
  @override
  bool get isAvailable => false;
  @override
  Future<void> ensureIdentity(LeaderboardIdentity identity) async {}
  @override
  Future<void> submitSnapshot(LeaderboardSnapshot snapshot) async {}
  @override
  Future<LeaderboardViewData> loadLeaderboard(LeaderboardMetric metric) async =>
      LeaderboardViewData(
        metric: metric,
        entries: const [],
        updatedAt: DateTime.now(),
        isUnavailable: true,
      );
}

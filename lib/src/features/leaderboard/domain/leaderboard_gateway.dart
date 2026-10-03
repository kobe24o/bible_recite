import 'leaderboard_models.dart';

final class LeaderboardIdentity {
  const LeaderboardIdentity({
    required this.displayName,
    required this.installationAlias,
  });

  final String displayName;
  final String installationAlias;
}

abstract interface class LeaderboardGateway {
  Future<void> ensureIdentity(LeaderboardIdentity identity);

  Future<void> submitSnapshot(LeaderboardSnapshot snapshot);

  Future<LeaderboardViewData> loadLeaderboard(LeaderboardMetric metric);
}

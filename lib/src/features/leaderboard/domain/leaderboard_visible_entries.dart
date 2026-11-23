import 'leaderboard_models.dart';

/// Ranks are global positions, including when the server returns sparse windows.
List<LeaderboardEntry> visibleLeaderboardEntries(
  Iterable<LeaderboardEntry> entries, {
  LeaderboardEntry? currentUser,
}) {
  final byRank = {for (final entry in entries) entry.rank: entry};
  if (currentUser != null) byRank[currentUser.rank] = currentUser;
  final sorted = byRank.values.toList()
    ..sort((a, b) => a.rank.compareTo(b.rank));
  if (sorted.isEmpty || sorted.last.rank <= 50) return sorted;
  final lastRank = sorted.last.rank;
  final ownRank =
      currentUser?.rank ??
      sorted.where((entry) => entry.isCurrentUser).firstOrNull?.rank;
  return sorted
      .where(
        (entry) =>
            entry.rank <= 10 ||
            entry.rank > lastRank - 10 ||
            (ownRank != null && (entry.rank - ownRank).abs() <= 10),
      )
      .toList(growable: false);
}

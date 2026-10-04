import '../domain/leaderboard_models.dart';

LeaderboardEntry decodeLeaderboardEntry(Map<String, dynamic> row) =>
    LeaderboardEntry(
      rank: (row['rank'] as num).toInt(),
      displayName: row['display_name'] as String,
      value: row['value'] as num,
      isCurrentUser: row['is_current_user'] == true,
    );
LeaderboardViewData decodeLeaderboard(
  LeaderboardMetric metric,
  Map<String, dynamic> json, {
  bool fromCache = false,
  bool unavailable = false,
}) => LeaderboardViewData(
  metric: metric,
  entries: (json['entries'] as List)
      .map(
        (row) => decodeLeaderboardEntry(Map<String, dynamic>.from(row as Map)),
      )
      .toList(growable: false),
  currentUser: json['current_user'] == null
      ? null
      : decodeLeaderboardEntry(
          Map<String, dynamic>.from(json['current_user'] as Map),
        ),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  isFromCache: fromCache,
  isUnavailable: unavailable,
);
Map<String, dynamic> encodeLeaderboard(LeaderboardViewData data) {
  Map<String, dynamic> row(LeaderboardEntry entry) => {
    'rank': entry.rank,
    'display_name': entry.displayName,
    'value': entry.value,
    'is_current_user': entry.isCurrentUser,
  };
  return {
    'entries': data.entries.map(row).toList(),
    'current_user': data.currentUser == null ? null : row(data.currentUser!),
    'updated_at': data.updatedAt.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> encodeSnapshot(LeaderboardSnapshot value) => {
  'total_sessions': value.totalSessions,
  'unique_verses': value.uniqueVerses,
  'total_recitation_seconds': value.totalRecitationSeconds,
  'max_day_streak': value.maxDayStreak,
  'current_day_streak': value.currentDayStreak,
  'devotion_days': value.devotionDays,
  'total_devotion_seconds': value.totalDevotionSeconds,
  'max_devotion_day_streak': value.maxDevotionDayStreak,
  'current_devotion_day_streak': value.currentDevotionDayStreak,
  'badge_awards': value.badgeAwards,
  'quiz_answered': value.quizAnswered,
  'quiz_correct': value.quizCorrect,
};

enum LeaderboardMetric {
  totalSessions,
  uniqueVerses,
  maxDayStreak,
  badgeAwards,
  totalRecitationSeconds,
  currentDayStreak,
  quizAccuracy;

  String get wireName => switch (this) {
    LeaderboardMetric.totalSessions => 'total_sessions',
    LeaderboardMetric.uniqueVerses => 'unique_verses',
    LeaderboardMetric.maxDayStreak => 'max_day_streak',
    LeaderboardMetric.badgeAwards => 'badge_awards',
    LeaderboardMetric.totalRecitationSeconds => 'total_recitation_seconds',
    LeaderboardMetric.currentDayStreak => 'current_day_streak',
    LeaderboardMetric.quizAccuracy => 'quiz_accuracy',
  };
}

final class LeaderboardSnapshot {
  const LeaderboardSnapshot({
    required this.totalSessions,
    required this.uniqueVerses,
    required this.maxDayStreak,
    required this.badgeAwards,
    required this.totalRecitationSeconds,
    required this.currentDayStreak,
    required this.quizAnswered,
    required this.quizCorrect,
  });

  final int totalSessions;
  final int uniqueVerses;
  final int maxDayStreak;
  final int badgeAwards;
  final int totalRecitationSeconds;
  final int currentDayStreak;
  final int quizAnswered;
  final int quizCorrect;

  bool get hasQuizAccuracy => quizAnswered > 0;
  double get quizAccuracy => hasQuizAccuracy ? quizCorrect / quizAnswered : 0;

  num valueFor(LeaderboardMetric metric) => switch (metric) {
    LeaderboardMetric.totalSessions => totalSessions,
    LeaderboardMetric.uniqueVerses => uniqueVerses,
    LeaderboardMetric.maxDayStreak => maxDayStreak,
    LeaderboardMetric.badgeAwards => badgeAwards,
    LeaderboardMetric.totalRecitationSeconds => totalRecitationSeconds,
    LeaderboardMetric.currentDayStreak => currentDayStreak,
    LeaderboardMetric.quizAccuracy => quizAccuracy,
  };
}

final class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.displayName,
    required this.value,
    this.isCurrentUser = false,
  });

  final int rank;
  final String displayName;
  final num value;
  final bool isCurrentUser;
}

final class LeaderboardViewData {
  const LeaderboardViewData({
    required this.metric,
    required this.entries,
    required this.updatedAt,
    this.currentUser,
    this.isFromCache = false,
  });

  final LeaderboardMetric metric;
  final List<LeaderboardEntry> entries;
  final DateTime updatedAt;
  final LeaderboardEntry? currentUser;
  final bool isFromCache;
}

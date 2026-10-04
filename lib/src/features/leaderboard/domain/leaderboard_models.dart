enum LeaderboardMetric {
  totalSessions,
  uniqueVerses,
  totalRecitationSeconds,
  maxDayStreak,
  currentDayStreak,
  devotionDays,
  totalDevotionSeconds,
  maxDevotionDayStreak,
  currentDevotionDayStreak,
  badgeAwards,
  quizAccuracy;

  String get wireName => switch (this) {
    LeaderboardMetric.totalSessions => 'total_sessions',
    LeaderboardMetric.uniqueVerses => 'unique_verses',
    LeaderboardMetric.totalRecitationSeconds => 'total_recitation_seconds',
    LeaderboardMetric.maxDayStreak => 'max_day_streak',
    LeaderboardMetric.currentDayStreak => 'current_day_streak',
    LeaderboardMetric.devotionDays => 'devotion_days',
    LeaderboardMetric.totalDevotionSeconds => 'total_devotion_seconds',
    LeaderboardMetric.maxDevotionDayStreak => 'max_devotion_day_streak',
    LeaderboardMetric.currentDevotionDayStreak => 'current_devotion_day_streak',
    LeaderboardMetric.badgeAwards => 'badge_awards',
    LeaderboardMetric.quizAccuracy => 'quiz_accuracy',
  };
}

final class LeaderboardSnapshot {
  const LeaderboardSnapshot({
    required this.totalSessions,
    required this.uniqueVerses,
    required this.totalRecitationSeconds,
    required this.maxDayStreak,
    required this.currentDayStreak,
    required this.devotionDays,
    required this.totalDevotionSeconds,
    required this.maxDevotionDayStreak,
    required this.currentDevotionDayStreak,
    required this.badgeAwards,
    required this.quizAnswered,
    required this.quizCorrect,
  });

  final int totalSessions;
  final int uniqueVerses;
  final int totalRecitationSeconds;
  final int maxDayStreak;
  final int currentDayStreak;
  final int devotionDays;
  final int totalDevotionSeconds;
  final int maxDevotionDayStreak;
  final int currentDevotionDayStreak;
  final int badgeAwards;
  final int quizAnswered;
  final int quizCorrect;

  bool get hasQuizAccuracy => quizAnswered > 0;
  double get quizAccuracy => hasQuizAccuracy ? quizCorrect / quizAnswered : 0;

  num valueFor(LeaderboardMetric metric) => switch (metric) {
    LeaderboardMetric.totalSessions => totalSessions,
    LeaderboardMetric.uniqueVerses => uniqueVerses,
    LeaderboardMetric.totalRecitationSeconds => totalRecitationSeconds,
    LeaderboardMetric.maxDayStreak => maxDayStreak,
    LeaderboardMetric.currentDayStreak => currentDayStreak,
    LeaderboardMetric.devotionDays => devotionDays,
    LeaderboardMetric.totalDevotionSeconds => totalDevotionSeconds,
    LeaderboardMetric.maxDevotionDayStreak => maxDevotionDayStreak,
    LeaderboardMetric.currentDevotionDayStreak => currentDevotionDayStreak,
    LeaderboardMetric.badgeAwards => badgeAwards,
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
    this.isUnavailable = false,
  });

  final LeaderboardMetric metric;
  final List<LeaderboardEntry> entries;
  final DateTime updatedAt;
  final LeaderboardEntry? currentUser;
  final bool isFromCache;
  final bool isUnavailable;
}

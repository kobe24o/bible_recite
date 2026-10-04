import '../../quiz/domain/quiz_result.dart';
import '../../statistics/domain/achievement.dart';
import '../../devotion/domain/devotion_activity.dart';
import '../../statistics/domain/recitation_result.dart';
import '../domain/leaderboard_models.dart';

LeaderboardSnapshot buildLeaderboardSnapshot({
  required RecitationSummary recitation,
  required LearningStats learning,
  required DevotionStats devotion,
  required QuizSummary quiz,
  required Iterable<AchievementProgress> achievements,
  int? totalBadgeAwards,
}) {
  final badgeAwards = achievements.fold<int>(
    0,
    (sum, achievement) =>
        sum + (achievement.unlockedAt == null ? 0 : achievement.awardCount),
  );
  return LeaderboardSnapshot(
    totalSessions: recitation.totalSessions,
    uniqueVerses: recitation.totalVerses,
    maxDayStreak: learning.maxDayStreak,
    badgeAwards: totalBadgeAwards ?? badgeAwards,
    totalRecitationSeconds: recitation.totalSeconds,
    currentDayStreak: learning.currentDayStreak,
    devotionDays: devotion.devotionDays,
    totalDevotionSeconds: devotion.totalSeconds,
    maxDevotionDayStreak: devotion.maxDayStreak,
    currentDevotionDayStreak: devotion.currentDayStreak,
    quizAnswered: quiz.totalAnswered,
    quizCorrect: quiz.totalCorrect,
  );
}

import 'package:bible_recite/src/features/leaderboard/application/leaderboard_snapshot_builder.dart';
import 'package:bible_recite/src/features/statistics/domain/achievement.dart';
import 'package:bible_recite/src/features/statistics/domain/recitation_result.dart';
import 'package:bible_recite/src/features/quiz/domain/quiz_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds all seven leaderboard values from local aggregates', () {
    final snapshot = buildLeaderboardSnapshot(
      recitation: const RecitationSummary(
        totalSessions: 4,
        totalVerses: 12,
        totalSeconds: 3661,
        averageAccuracy: 0.9,
      ),
      learning: const LearningStats(
        recitationDays: 5,
        currentDayStreak: 3,
        maxDayStreak: 7,
        currentVerseStreak: 8,
        maxVerseStreak: 18,
      ),
      quiz: const QuizSummary(
        totalAnswered: 10,
        totalCorrect: 8,
        currentCorrectStreak: 2,
        maxCorrectStreak: 4,
      ),
      achievements: [
        _progress('earned-once', unlockedAt: DateTime(2026), awardCount: 1),
        _progress(
          'earned-repeatable',
          unlockedAt: DateTime(2026),
          awardCount: 2,
        ),
        _progress('locked', awardCount: 99),
      ],
    );

    expect(snapshot.totalSessions, 4);
    expect(snapshot.uniqueVerses, 12);
    expect(snapshot.maxDayStreak, 7);
    expect(snapshot.badgeAwards, 3);
    expect(snapshot.totalRecitationSeconds, 3661);
    expect(snapshot.currentDayStreak, 3);
    expect(snapshot.quizAnswered, 10);
    expect(snapshot.quizCorrect, 8);
    expect(snapshot.quizAccuracy, 0.8);
  });

  test('excludes locked badges and retains repeatable award counts', () {
    final snapshot = buildLeaderboardSnapshot(
      recitation: const RecitationSummary(
        totalSessions: 0,
        totalVerses: 0,
        totalSeconds: 0,
        averageAccuracy: 0,
      ),
      learning: const LearningStats(
        recitationDays: 0,
        currentDayStreak: 0,
        maxDayStreak: 0,
        currentVerseStreak: 0,
        maxVerseStreak: 0,
      ),
      quiz: const QuizSummary(
        totalAnswered: 0,
        totalCorrect: 0,
        currentCorrectStreak: 0,
        maxCorrectStreak: 0,
      ),
      achievements: [
        _progress('locked', awardCount: 5),
        _progress('repeatable', unlockedAt: DateTime(2026), awardCount: 3),
      ],
    );

    expect(snapshot.badgeAwards, 3);
    expect(snapshot.hasQuizAccuracy, isFalse);
  });
}

AchievementProgress _progress(
  String id, {
  DateTime? unlockedAt,
  int awardCount = 0,
}) => AchievementProgress(
  definition: AchievementDefinition(
    id: id,
    title: id,
    description: id,
    metric: AchievementMetric.sessions,
    target: 1,
    repeatable: awardCount > 1,
  ),
  current: 1,
  satisfied: unlockedAt != null,
  unlockedAt: unlockedAt,
  awardCount: awardCount,
);

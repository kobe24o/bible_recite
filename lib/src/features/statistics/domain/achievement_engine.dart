import 'achievement.dart';

final class AchievementEngine {
  const AchievementEngine();

  List<AchievementProgress> evaluate(AchievementSnapshot snapshot) => [
    for (final definition in achievementDefinitions)
      AchievementProgress(
        definition: definition,
        current: _current(definition.metric, snapshot),
        satisfied: _current(definition.metric, snapshot) >= definition.target,
      ),
  ];

  double _current(AchievementMetric metric, AchievementSnapshot snapshot) =>
      switch (metric) {
        AchievementMetric.sessions => snapshot.sessionCount.toDouble(),
        AchievementMetric.streak => snapshot.activeDayStreak.toDouble(),
        AchievementMetric.verses => snapshot.completedVerses.toDouble(),
        AchievementMetric.accuracy => snapshot.maxAccuracy,
        AchievementMetric.perfectLong => snapshot.hasPerfectLongResult ? 1 : 0,
        AchievementMetric.chapters => snapshot.completedChapters.toDouble(),
        AchievementMetric.plans => snapshot.planCount.toDouble(),
        AchievementMetric.completedPlans =>
          snapshot.completedPlanCount.toDouble(),
      };
}

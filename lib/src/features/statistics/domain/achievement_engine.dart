import 'achievement.dart';

final class RepeatedAchievementProgress {
  const RepeatedAchievementProgress({
    required this.awardCount,
    required this.progress,
  });

  final int awardCount;
  final double progress;
}

RepeatedAchievementProgress calculateRepeatedAchievementProgress(
  Iterable<int> verseCounts,
) {
  final counts = verseCounts.toList(growable: false);
  if (counts.isEmpty) {
    return const RepeatedAchievementProgress(awardCount: 0, progress: 0);
  }
  final awardCount = counts.reduce(
    (left, right) => left < right ? left : right,
  );
  final nextRoundVerseCount = counts
      .where((count) => count >= awardCount + 1)
      .length;
  return RepeatedAchievementProgress(
    awardCount: awardCount,
    progress: awardCount + nextRoundVerseCount / counts.length,
  );
}

final class AchievementEngine {
  const AchievementEngine();

  List<AchievementProgress> evaluate(AchievementSnapshot snapshot) => [
    for (final definition in achievementDefinitionsFor(snapshot))
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
        AchievementMetric.recitationDays => snapshot.recitationDays.toDouble(),
      };
}

import 'package:bible_recite/src/features/statistics/domain/achievement.dart';
import 'package:bible_recite/src/features/statistics/domain/achievement_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'an unlocked achievement keeps 100 percent when its metric decreases',
    () {
      final progress = AchievementProgress(
        definition: achievementDefinitions.singleWhere(
          (definition) => definition.id == 'plan_complete',
        ),
        current: 0,
        satisfied: false,
        unlockedAt: DateTime(2026, 8, 5, 12),
      );

      expect(progress.fraction, 1);
    },
  );

  test('unlocks encouragement milestones at their exact thresholds', () {
    final progress = const AchievementEngine().evaluate(
      const AchievementSnapshot(
        sessionCount: 10,
        activeDayStreak: 3,
        completedVerses: 50,
        maxAccuracy: 0.9,
        hasPerfectLongResult: false,
        completedChapters: 0,
        planCount: 1,
        completedPlanCount: 0,
      ),
    );
    final unlocked = {
      for (final item in progress.where((item) => item.satisfied))
        item.definition.id,
    };

    expect(
      unlocked,
      containsAll([
        'first_recitation',
        'sessions_3',
        'sessions_10',
        'streak_3',
        'verses_10',
        'verses_50',
        'accuracy_80',
        'accuracy_90',
        'first_plan',
      ]),
    );
    expect(unlocked, isNot(contains('sessions_25')));
    expect(unlocked, isNot(contains('perfect_100')));
  });

  test('requires twenty comparable characters for perfect achievement', () {
    final withoutLength = const AchievementEngine().evaluate(
      const AchievementSnapshot(
        sessionCount: 1,
        activeDayStreak: 1,
        completedVerses: 1,
        maxAccuracy: 1,
        hasPerfectLongResult: false,
        completedChapters: 0,
        planCount: 0,
        completedPlanCount: 0,
      ),
    );
    final withLength = const AchievementEngine().evaluate(
      const AchievementSnapshot(
        sessionCount: 1,
        activeDayStreak: 1,
        completedVerses: 1,
        maxAccuracy: 1,
        hasPerfectLongResult: true,
        completedChapters: 0,
        planCount: 0,
        completedPlanCount: 0,
      ),
    );

    expect(
      withoutLength
          .singleWhere((item) => item.definition.id == 'perfect_100')
          .satisfied,
      isFalse,
    );
    expect(
      withLength
          .singleWhere((item) => item.definition.id == 'perfect_100')
          .satisfied,
      isTrue,
    );
  });

  test('unlocks chapter and completed plan achievements', () {
    final progress = const AchievementEngine().evaluate(
      const AchievementSnapshot(
        sessionCount: 1,
        activeDayStreak: 1,
        completedVerses: 1,
        maxAccuracy: 0.5,
        hasPerfectLongResult: false,
        completedChapters: 1,
        planCount: 1,
        completedPlanCount: 1,
      ),
    );

    expect(
      progress
          .singleWhere((item) => item.definition.id == 'chapter_complete')
          .satisfied,
      isTrue,
    );
    expect(
      progress
          .singleWhere((item) => item.definition.id == 'plan_complete')
          .satisfied,
      isTrue,
    );
  });

  test('keeps repeatable achievement progress above one completed round', () {
    const definition = AchievementDefinition(
      id: 'book_complete_JHN',
      title: '约翰福音勋章',
      description: '完成约翰福音全部经文',
      metric: AchievementMetric.sessions,
      target: 1,
      repeatable: true,
    );
    final progress = AchievementProgress(
      definition: definition,
      current: 1.1,
      satisfied: true,
      unlockedAt: DateTime(2026, 8, 26),
      awardCount: 1,
    );

    expect(progress.fraction, closeTo(1.1, 0.0001));
    expect(progress.awardCount, 1);
  });

  test(
    'uses the minimum round and counts verses at or above the next round',
    () {
      final result = calculateRepeatedAchievementProgress([
        ...List<int>.filled(9, 1),
        2,
      ]);

      expect(result.awardCount, 1);
      expect(result.progress, closeTo(1.1, 0.0001));

      final laterRounds = calculateRepeatedAchievementProgress([2, 3, 4]);
      expect(laterRounds.awardCount, 2);
      expect(laterRounds.progress, closeTo(2 + 2 / 3, 0.0001));
    },
  );
}

import 'package:bible_recite/src/features/statistics/domain/achievement.dart';
import 'package:bible_recite/src/features/statistics/domain/achievement_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}

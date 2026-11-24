import 'package:bible_recite/src/features/leaderboard/application/leaderboard_providers.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:bible_recite/src/features/statistics/domain/achievement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'snapshot includes repeated awards in the displayed collection',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final displayed = await repository.syncExternalAchievements(
        [
          const AchievementDefinition(
            id: 'visible',
            title: 'test',
            description: '',
            metric: AchievementMetric.sessions,
            target: 1,
            repeatable: true,
          ),
        ],
        {'visible'},
        {'visible': 3},
      );
      expect(
        (await loadLeaderboardSnapshot(
          repository,
          displayedAchievements: displayed,
        )).badgeAwards,
        3,
      );
    },
  );

  test(
    'snapshot excludes awards whose definition is no longer displayed',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      await repository.syncExternalAchievementsWithUnlocks(
        [
          const AchievementDefinition(
            id: 'external',
            title: 'test',
            description: '',
            metric: AchievementMetric.sessions,
            target: 1,
            repeatable: true,
          ),
        ],
        {'external'},
        {'external': 3},
      );
      expect((await loadLeaderboardSnapshot(repository)).badgeAwards, 0);
      expect(
        await repository.getSetting('leaderboard_dirty_since', ''),
        isNotEmpty,
      );
    },
  );
}

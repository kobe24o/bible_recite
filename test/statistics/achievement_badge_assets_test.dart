import 'package:bible_recite/src/features/statistics/presentation/achievement_badge_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps dynamic achievement ids to bundled badge artwork', () {
    expect(
      achievementBadgeAssetPath('book_complete_1JN'),
      'assets/achievements/generated/book_1_john.png',
    );
    expect(
      achievementBadgeAssetPath('days_60'),
      'assets/achievements/generated/recitation_days_30n_template.png',
    );
    expect(
      achievementBadgeAssetPath('streak_30'),
      'assets/achievements/generated/streak_30n_template.png',
    );
    expect(
      achievementBadgeAssetPath('preset_plan_grace-path'),
      'assets/achievements/generated/preset_plan.png',
    );
  });
}

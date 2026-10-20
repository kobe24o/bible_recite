import 'package:bible_recite/src/features/statistics/domain/achievement.dart';
import 'package:bible_recite/src/features/statistics/presentation/achievement_unlock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('incomplete book detail floors progress and remains locked', (
    tester,
  ) async {
    const progress = AchievementProgress(
      definition: AchievementDefinition(
        id: 'book_complete_EXO',
        title: '出埃及记勋章',
        description: '完成出埃及记全部经文',
        metric: AchievementMetric.sessions,
        target: 1,
        repeatable: true,
      ),
      current: 1212 / 1213,
      satisfied: false,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AchievementUnlockDialog(
            progress: progress,
            newlyUnlocked: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前进度：99%'), findsOneWidget);
    expect(find.text('当前进度：100%'), findsNothing);
    expect(find.text('已获得'), findsNothing);
  });
}

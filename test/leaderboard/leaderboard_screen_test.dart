import 'package:bible_recite/src/features/leaderboard/application/leaderboard_providers.dart';
import 'package:bible_recite/src/features/leaderboard/application/leaderboard_sync_controller.dart';
import 'package:bible_recite/src/features/leaderboard/domain/leaderboard_models.dart';
import 'package:bible_recite/src/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'leaderboard_sync_controller_test.dart'
    show MemoryGateway, snapshot, identity;

class ScreenGateway extends MemoryGateway {
  @override
  Future<LeaderboardViewData> loadLeaderboard(LeaderboardMetric metric) async {
    if (this.fail) throw StateError('offline');
    return LeaderboardViewData(
      metric: metric,
      entries: const [
        LeaderboardEntry(
          rank: 1,
          displayName: '路得',
          value: 0.5,
          isCurrentUser: true,
        ),
      ],
      currentUser: const LeaderboardEntry(
        rank: 1,
        displayName: '路得',
        value: 0.5,
        isCurrentUser: true,
      ),
      updatedAt: DateTime(2026),
    );
  }
}

void main() {
  late SqlitePlanRepository repo;
  late ScreenGateway gateway;
  late LeaderboardSyncController controller;
  setUp(() {
    repo = SqlitePlanRepository(sqlite3.openInMemory());
    gateway = ScreenGateway();
    controller = LeaderboardSyncController(
      repository: repo,
      gateway: gateway,
      snapshotLoader: () async => snapshot,
      identityLoader: () async => identity,
    );
  });
  tearDown(() => repo.close());
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leaderboardSyncControllerProvider.overrideWith(
            (ref) async => controller,
          ),
          leaderboardSnapshotProvider.overrideWith((ref) async => snapshot),
        ],
        child: const MaterialApp(home: LeaderboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'eleven ordered metrics distinguish recitation and devotion streaks',
    (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('leaderboard-current-user')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('leaderboard-metric-quizAccuracy')),
      );
      await tester.tap(
        find.byKey(const Key('leaderboard-metric-quizAccuracy')),
      );
      await tester.pumpAndSettle();
      expect(find.text('50.0%'), findsWidgets);
      expect(find.byType(ChoiceChip), findsNWidgets(11));
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .map((chip) => (chip.label as Text).data),
        [
          '累计背诵次数',
          '已背诵不同经节',
          '累计背诵时长',
          '最高连续背诵天数',
          '当前连续背诵天数',
          '累计灵修天数',
          '累计灵修时长',
          '最高连续灵修天数',
          '当前连续灵修天数',
          '勋章数量',
          '答题正确率',
        ],
      );
    },
  );
  testWidgets('cached rows survive explicit refresh failure', (tester) async {
    await controller.refresh(LeaderboardMetric.totalSessions);
    gateway.fail = true;
    await pump(tester);
    await tester.tap(find.byKey(const Key('leaderboard-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('路得'), findsOneWidget);
    expect(find.textContaining('暂无法更新'), findsOneWidget);
  });
  testWidgets('offline empty board still renders local aggregates', (
    tester,
  ) async {
    gateway.fail = true;
    await pump(tester);
    expect(find.text('暂无排名数据'), findsOneWidget);
    expect(find.byKey(const Key('leaderboard-local-summary')), findsOneWidget);
    expect(find.textContaining('暂无法更新'), findsOneWidget);
  });
}

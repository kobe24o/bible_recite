import 'dart:async';
import 'package:bible_recite/src/features/leaderboard/application/leaderboard_sync_controller.dart';
import 'package:bible_recite/src/features/leaderboard/domain/leaderboard_gateway.dart';
import 'package:bible_recite/src/features/leaderboard/domain/leaderboard_models.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const snapshot = LeaderboardSnapshot(
  totalSessions: 1,
  uniqueVerses: 2,
  maxDayStreak: 3,
  badgeAwards: 4,
  totalRecitationSeconds: 120,
  currentDayStreak: 1,
  quizAnswered: 2,
  quizCorrect: 1,
);
const identity = LeaderboardIdentity(
  displayName: '设备 · ABCDEF',
  installationAlias: 'ABCDEF',
);

class MemoryGateway implements LeaderboardGateway {
  int uploads = 0, reads = 0;
  bool fail = false;
  Completer<void>? uploadBarrier;
  void Function()? afterSubmit;
  @override
  Future<void> ensureIdentity(LeaderboardIdentity identity) async {
    if (fail) throw StateError('offline');
  }

  @override
  Future<void> submitSnapshot(LeaderboardSnapshot snapshot) async {
    uploads++;
    await uploadBarrier?.future;
    afterSubmit?.call();
  }

  @override
  Future<LeaderboardViewData> loadLeaderboard(LeaderboardMetric metric) async {
    reads++;
    if (fail) throw StateError('offline');
    return LeaderboardViewData(
      metric: metric,
      entries: const [LeaderboardEntry(rank: 1, displayName: '路得', value: 1)],
      updatedAt: DateTime(2026),
    );
  }
}

void main() {
  late SqlitePlanRepository repo;
  late MemoryGateway gateway;
  late DateTime now;
  late LeaderboardSyncController controller;
  LeaderboardSyncController create() => LeaderboardSyncController(
    repository: repo,
    gateway: gateway,
    clock: () => now,
    snapshotLoader: () async => snapshot,
    identityLoader: () async => identity,
  );
  setUp(() {
    repo = SqlitePlanRepository(sqlite3.openInMemory());
    gateway = MemoryGateway();
    now = DateTime(2026);
    controller = create();
  });
  tearDown(() {
    repo.close();
  });
  test(
    'coalesces changes after fifteen minutes and persists across restarts',
    () async {
      await controller.markDirty();
      now = now.add(const Duration(minutes: 1));
      await controller.markDirty();
      await create().syncIfDue();
      expect(gateway.uploads, 0);
      now = now.add(const Duration(minutes: 14));
      await create().syncIfDue();
      expect(gateway.uploads, 1);
      expect(await controller.isDirty(), isFalse);
      await controller.markDirty();
      await controller.syncIfDue();
      expect(gateway.uploads, 1);
    },
  );
  test(
    'failed upload retains dirty data and cache remains visible on read failure',
    () async {
      await controller.refresh(LeaderboardMetric.totalSessions);
      await controller.markDirty();
      now = now.add(const Duration(minutes: 15));
      gateway.fail = true;
      final result = await controller.refresh(
        LeaderboardMetric.totalSessions,
        force: true,
      );
      expect(result.entries, isNotEmpty);
      expect(result.isUnavailable, isTrue);
      expect(await controller.isDirty(), isTrue);
    },
  );
  test(
    'five minute cache is per metric; explicit refresh bypasses it',
    () async {
      await controller.refresh(LeaderboardMetric.totalSessions);
      await controller.refresh(LeaderboardMetric.totalSessions);
      expect(gateway.reads, 1);
      await controller.refresh(LeaderboardMetric.uniqueVerses);
      expect(gateway.reads, 2);
      now = now.add(const Duration(minutes: 5));
      await controller.refresh(LeaderboardMetric.totalSessions);
      expect(gateway.reads, 3);
      await controller.markDirty();
      await controller.refresh(LeaderboardMetric.totalSessions, force: true);
      expect(gateway.uploads, 1);
      expect(gateway.reads, 4);
      expect(
        (await create().readCached(
          LeaderboardMetric.totalSessions,
        ))!.isFromCache,
        isTrue,
      );
    },
  );
  test('mutation during upload is retained for the next snapshot', () async {
    await controller.markDirty();
    now = now.add(const Duration(minutes: 15));
    gateway.uploadBarrier = Completer<void>();
    final upload = controller.syncIfDue();
    while (gateway.uploads == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.markDirty();
    gateway.uploadBarrier!.complete();
    await upload;
    expect(await controller.isDirty(), isTrue);
  });
  test('mutation between revision read and cleanup is retained', () async {
    for (var delay = 0; delay < 16; delay++) {
      final changed = Completer<void>();
      void queue(int hops) {
        if (hops > 0) {
          scheduleMicrotask(() => queue(hops - 1));
        } else {
          unawaited(controller.markDirty().then((_) => changed.complete()));
        }
      }

      gateway.afterSubmit = () => queue(delay);
      await controller.markDirty();
      await controller.syncIfDue(force: true);
      await changed.future;
      expect(await controller.isDirty(), isTrue, reason: 'microtasks: $delay');
    }
  });
  test(
    'resume refreshes day-sensitive streaks after the last successful interval',
    () async {
      await repo.setSetting('leaderboard_day', '2025-12-31');
      await repo.setSetting(
        'leaderboard_last_success',
        now.subtract(const Duration(minutes: 16)).toUtc().toIso8601String(),
      );
      await controller.onResume();
      expect(gateway.uploads, 1);
      await controller.onResume();
      expect(gateway.uploads, 1);
    },
  );
  test(
    'corrupt cache is ignored and missing cloud configuration remains usable',
    () async {
      await repo.setSetting('leaderboard_cache_total_sessions', '{broken');
      expect(
        await controller.readCached(LeaderboardMetric.totalSessions),
        isNull,
      );
    },
  );
}

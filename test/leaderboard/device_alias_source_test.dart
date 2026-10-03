import 'package:bible_recite/src/features/leaderboard/data/device_alias_source.dart';
import 'package:bible_recite/src/features/leaderboard/data/leaderboard_config.dart';
import 'package:bible_recite/src/features/plans/data/sqlite_plan_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('blank configuration never enables cloud access', () {
    expect(const LeaderboardConfig('', '').isConfigured, isFalse);
    expect(
      const LeaderboardConfig('https://example.supabase.co', ' ').isConfigured,
      isFalse,
    );
    expect(
      const LeaderboardConfig(
        'https://example.supabase.co',
        'placeholder',
      ).isConfigured,
      isTrue,
    );
  });
  test('reuses a safe installation alias across restarts', () async {
    final repository = SqlitePlanRepository(sqlite3.openInMemory());
    addTearDown(repository.close);
    final source = DeviceAliasSource(
      modelReader: () async => 'Pixel 8',
      aliasGenerator: () => 'A1B2C3',
    );
    expect(await source.loadOrCreate(repository), 'Pixel 8 · A1B2C3');
    final restarted = DeviceAliasSource(
      modelReader: () async => 'Pixel 8',
      aliasGenerator: () => 'ZZZZZZ',
    );
    expect(await restarted.loadOrCreate(repository), 'Pixel 8 · A1B2C3');
  });
  test(
    'unavailable or unsafe device model falls back without a hardware ID',
    () async {
      final repository = SqlitePlanRepository(sqlite3.openInMemory());
      addTearDown(repository.close);
      final source = DeviceAliasSource(
        modelReader: () async => throw StateError('unavailable'),
        aliasGenerator: () => 'ABCDEF',
      );
      expect(await source.loadOrCreate(repository), '本机设备 · ABCDEF');
    },
  );
}

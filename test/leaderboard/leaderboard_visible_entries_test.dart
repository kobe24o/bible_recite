import 'package:bible_recite/src/features/leaderboard/domain/leaderboard_models.dart';
import 'package:bible_recite/src/features/leaderboard/domain/leaderboard_visible_entries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<LeaderboardEntry> board(int count, {int? caller}) => [
    for (var rank = 1; rank <= count; rank++)
      LeaderboardEntry(
        rank: rank,
        displayName: 'User $rank',
        value: count - rank,
        isCurrentUser: rank == caller,
      ),
  ];
  test('up to fifty participants are all visible', () {
    expect(
      visibleLeaderboardEntries(board(50, caller: 25)).map((e) => e.rank),
      orderedEquals(List.generate(50, (i) => i + 1)),
    );
  });
  test(
    'large board keeps leaders, ten neighbors on either side, and last ten',
    () {
      final visible = visibleLeaderboardEntries(board(1000, caller: 500));
      expect(
        visible.map((e) => e.rank),
        orderedEquals([
          ...List.generate(10, (i) => i + 1),
          ...List.generate(21, (i) => i + 490),
          ...List.generate(10, (i) => i + 991),
        ]),
      );
      expect(visible.where((e) => e.isCurrentUser).single.rank, 500);
    },
  );
  test('overlapping windows merge without duplicate names', () {
    expect(
      visibleLeaderboardEntries(board(100, caller: 5)).map((e) => e.rank),
      orderedEquals([
        ...List.generate(15, (i) => i + 1),
        ...List.generate(10, (i) => i + 91),
      ]),
    );
    expect(
      visibleLeaderboardEntries(board(100, caller: 96)).map((e) => e.rank),
      orderedEquals([
        ...List.generate(10, (i) => i + 1),
        ...List.generate(15, (i) => i + 86),
      ]),
    );
  });
  test('sparse server response keeps every requested window', () {
    final all = board(1000, caller: 500);
    final sparse = [
      ...all.take(10),
      ...all.skip(489).take(21),
      ...all.skip(990),
    ];
    expect(visibleLeaderboardEntries(sparse), orderedEquals(sparse));
  });
  test('unranked user sees first and last ten', () {
    expect(
      visibleLeaderboardEntries(board(100)).map((e) => e.rank),
      orderedEquals([
        ...List.generate(10, (i) => i + 1),
        ...List.generate(10, (i) => i + 91),
      ]),
    );
  });
}

import 'package:bible_recite/src/features/leaderboard/data/supabase_leaderboard_gateway.dart';
import 'package:bible_recite/src/features/leaderboard/data/offline_leaderboard_gateway.dart';
import 'package:bible_recite/src/features/leaderboard/domain/leaderboard_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'leaderboard_sync_controller_test.dart' show snapshot, identity;

class RpcTransport implements LeaderboardTransport {
  @override
  bool hasSession = false;
  int signIns = 0;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<void> signInAnonymously() async {
    signIns++;
    hasSession = true;
  }

  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    return {
      'entries': [
        {
          'rank': 1,
          'display_name': '路得',
          'value': 0.5,
          'is_current_user': true,
        },
      ],
      'current_user': {
        'rank': 1,
        'display_name': '路得',
        'value': 0.5,
        'is_current_user': true,
      },
      'updated_at': '2026-10-03T00:00:00Z',
    };
  }
}

void main() {
  test(
    'anonymous identity is reused and submission contains only aggregates',
    () async {
      final transport = RpcTransport();
      final gateway = SupabaseLeaderboardGateway(transport);
      await gateway.ensureIdentity(identity);
      await gateway.ensureIdentity(identity);
      await gateway.submitSnapshot(snapshot);
      expect(transport.signIns, 1);
      expect(transport.calls.single.$1, 'submit_leaderboard_snapshot');
      expect(transport.calls.single.$2, {
        'display_name': identity.displayName,
        'install_alias': identity.installationAlias,
        'total_sessions': 1,
        'unique_verses': 2,
        'max_day_streak': 3,
        'badge_awards': 4,
        'total_recitation_seconds': 120,
        'current_day_streak': 1,
        'devotion_days': 5,
        'total_devotion_seconds': 300,
        'max_devotion_day_streak': 4,
        'current_devotion_day_streak': 2,
        'quiz_answered': 2,
        'quiz_correct': 1,
      });
    },
  );
  test('one read RPC returns top rows and caller rank', () async {
    final transport = RpcTransport();
    final gateway = SupabaseLeaderboardGateway(transport);
    await gateway.ensureIdentity(identity);
    final result = await gateway.loadLeaderboard(
      LeaderboardMetric.quizAccuracy,
    );
    expect(transport.calls.single.$2, {
      'metric': 'quiz_accuracy',
      'limit_count': 50,
    });
    expect(result.currentUser!.isCurrentUser, isTrue);
    expect(result.entries.single.value, 0.5);
  });
  test(
    'offline gateway never needs authentication and reports unavailable',
    () async {
      final gateway = OfflineLeaderboardGateway();
      await gateway.ensureIdentity(identity);
      await gateway.submitSnapshot(snapshot);
      final result = await gateway.loadLeaderboard(
        LeaderboardMetric.quizAccuracy,
      );
      expect(result.entries, isEmpty);
      expect(result.currentUser, isNull);
      expect(result.isUnavailable, isTrue);
    },
  );
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/leaderboard_gateway.dart';
import '../domain/leaderboard_models.dart';
import 'leaderboard_codec.dart';

/// Backend transport is replaceable without importing Supabase in application/UI.
abstract interface class LeaderboardTransport {
  bool get hasSession;
  Future<void> signInAnonymously();
  Future<dynamic> rpc(String name, Map<String, dynamic> params);
}

final class SupabaseLeaderboardTransport implements LeaderboardTransport {
  SupabaseLeaderboardTransport(this.client);
  final SupabaseClient client;
  @override
  bool get hasSession => client.auth.currentSession != null;
  @override
  Future<void> signInAnonymously() async {
    await client.auth.signInAnonymously();
  }

  @override
  Future<dynamic> rpc(String name, Map<String, dynamic> params) =>
      client.rpc(name, params: params);
}

final class SupabaseLeaderboardGateway implements LeaderboardGateway {
  SupabaseLeaderboardGateway(this.transport);
  final LeaderboardTransport transport;
  LeaderboardIdentity? _identity;
  Future<void>? _signIn;
  Future<void> _authenticate() async {
    if (transport.hasSession) return;
    final pending = _signIn;
    if (pending != null) {
      await pending;
      return;
    }
    final request = transport.signInAnonymously();
    _signIn = request;
    try {
      await request;
    } finally {
      _signIn = null;
    }
  }

  @override
  Future<void> ensureIdentity(LeaderboardIdentity identity) async {
    _identity = identity;
    await _authenticate();
  }

  @override
  Future<void> submitSnapshot(LeaderboardSnapshot snapshot) async {
    await _authenticate();
    final identity = _identity;
    if (identity == null) {
      throw StateError('leaderboard identity not initialized');
    }
    await transport.rpc('submit_leaderboard_snapshot', {
      'display_name': identity.displayName,
      'install_alias': identity.installationAlias,
      ...encodeSnapshot(snapshot),
    });
  }

  @override
  Future<LeaderboardViewData> loadLeaderboard(LeaderboardMetric metric) async {
    await _authenticate();
    final data = await transport.rpc('get_leaderboard', {
      'metric': metric.wireName,
      'limit_count': 50,
    });
    return decodeLeaderboard(metric, Map<String, dynamic>.from(data as Map));
  }
}

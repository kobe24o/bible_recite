import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/leaderboard_providers.dart';
import '../domain/leaderboard_models.dart';

extension LeaderboardMetricLabel on LeaderboardMetric {
  String get label => switch (this) {
    LeaderboardMetric.totalSessions => '累计背诵次数',
    LeaderboardMetric.uniqueVerses => '已背诵不同经节',
    LeaderboardMetric.maxDayStreak => '最高连续天数',
    LeaderboardMetric.badgeAwards => '勋章数量',
    LeaderboardMetric.totalRecitationSeconds => '累计背诵时长',
    LeaderboardMetric.currentDayStreak => '当前连续天数',
    LeaderboardMetric.quizAccuracy => '答题正确率',
  };
  String format(num value) => switch (this) {
    LeaderboardMetric.quizAccuracy => '${(value * 100).toStringAsFixed(1)}%',
    LeaderboardMetric.totalRecitationSeconds =>
      '${value.toInt() ~/ 3600} 小时 ${value.toInt() % 3600 ~/ 60} 分钟',
    _ => '${value.toInt()}',
  };
}

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  LeaderboardMetric _metric = LeaderboardMetric.totalSessions;
  LeaderboardViewData? _data;
  bool _loading = true;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final request = ++_request;
    final metric = _metric;
    try {
      final controller = await ref.read(
        leaderboardSyncControllerProvider.future,
      );
      final cached = await controller.readCached(metric);
      if (!mounted || request != _request) return;
      if (cached != null) {
        setState(() {
          _data = cached;
          _loading = false;
        });
      }
      final data = await controller.refresh(metric, force: force);
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _loading = false;
      });
      ref.invalidate(leaderboardSnapshotProvider);
      ref.invalidate(leaderboardLastSyncProvider);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _data = LeaderboardViewData(
          metric: metric,
          entries: _data?.entries ?? const [],
          currentUser: _data?.currentUser,
          updatedAt: _data?.updatedAt ?? DateTime.now(),
          isFromCache: _data != null,
          isUnavailable: true,
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(leaderboardSnapshotProvider).asData?.value;
    final data = _data;
    final caller = data?.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        actions: [
          IconButton(
            key: const Key('leaderboard-refresh'),
            tooltip: '刷新排行榜',
            onPressed: () => _load(force: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              key: const Key('leaderboard-local-summary'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('我的本地数据'),
                    Text(
                      local == null
                          ? '读取中…'
                          : '${_metric.label}：${_metric == LeaderboardMetric.quizAccuracy && !local.hasQuizAccuracy ? '暂无答题记录，暂不参与排名' : _metric.format(local.valueFor(_metric))}',
                    ),
                  ],
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final metric in LeaderboardMetric.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('leaderboard-metric-${metric.name}'),
                        label: Text(metric.label),
                        selected: metric == _metric,
                        onSelected: (selected) {
                          if (!selected) return;
                          setState(() {
                            _metric = metric;
                            _data = null;
                            _loading = true;
                          });
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (data?.isUnavailable == true)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂无法更新，仍可查看本地数据与缓存榜单'),
              ),
            if (data != null &&
                (data.entries.isNotEmpty || !data.isUnavailable))
              Text(
                '${data.isFromCache ? '缓存 · ' : ''}更新时间：${data.updatedAt.toLocal().toString().split('.').first}',
              ),
            if (!_loading && (data?.entries.isEmpty ?? true))
              const Padding(padding: EdgeInsets.all(24), child: Text('暂无排名数据')),
            for (final entry in data?.entries ?? <LeaderboardEntry>[])
              _row(entry),
            if (caller != null &&
                !(data?.entries.any((row) => row.isCurrentUser) ?? false)) ...[
              const Divider(),
              const Text('我的排名'),
              _row(caller),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(LeaderboardEntry entry) => Card(
    color: entry.isCurrentUser
        ? Theme.of(context).colorScheme.primaryContainer
        : null,
    child: ListTile(
      key: entry.isCurrentUser ? const Key('leaderboard-current-user') : null,
      leading: Text('${entry.rank}'),
      title: Text(entry.displayName),
      subtitle: entry.isCurrentUser ? const Text('我') : null,
      trailing: Text(_metric.format(entry.value)),
    ),
  );
}

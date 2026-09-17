import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../scripture/application/scripture_providers.dart';
import '../application/devotion_providers.dart';
import '../domain/devotion_models.dart';

String devotionDateLabel(DateTime date) =>
    date.toIso8601String().substring(0, 10);

String devotionPassageLabel(DevotionPassage passage, String bookName) =>
    '$bookName ${passage.startChapter}:${passage.startVerse}–'
    '${passage.startChapter == passage.endChapter ? '' : '${passage.endChapter}:'}${passage.endVerse}';

class DevotionOverviewCard extends ConsumerWidget {
  const DevotionOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifest = ref.watch(cachedDevotionManifestProvider);
    return Card(
      child: Column(
        children: [
          ListTile(
            key: const Key('open-devotion-schedule'),
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('年度灵修'),
            subtitle: manifest.when(
              loading: () => const Text('正在读取日程…'),
              error: (_, _) => const Text('无法读取日程，请重试'),
              data: (value) => Text(
                value == null
                    ? '尚未缓存日程，联网同步后可离线阅读'
                    : '已缓存 ${value.years.map((year) => year.year).join('、')} 年 · 修订 ${value.revision}',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/devotion'),
          ),
          const DevotionSyncStatus(),
        ],
      ),
    );
  }
}

class DevotionSyncStatus extends ConsumerWidget {
  const DevotionSyncStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(devotionSyncProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sync.hasError) const Text('同步失败，请检查网络后重试。已有缓存仍可离线阅读。'),
          if (sync.isLoading) const LinearProgressIndicator(),
          TextButton.icon(
            key: const Key('sync-devotion'),
            onPressed: sync.isLoading
                ? null
                : () => ref.read(devotionSyncProvider.notifier).sync(),
            icon: const Icon(Icons.sync),
            label: Text(
              sync.isLoading
                  ? '正在同步…'
                  : sync.hasError
                  ? '重试同步'
                  : '同步灵修日程',
            ),
          ),
        ],
      ),
    );
  }
}

class DevotionScheduleScreen extends ConsumerStatefulWidget {
  const DevotionScheduleScreen({super.key});

  @override
  ConsumerState<DevotionScheduleScreen> createState() =>
      _DevotionScheduleScreenState();
}

class _DevotionScheduleScreenState
    extends ConsumerState<DevotionScheduleScreen> {
  final _scrollController = ScrollController();
  final _todayKey = GlobalKey();
  bool _positioned = false;
  bool _userScrolled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manifest = ref.watch(cachedDevotionManifestProvider);
    final today = devotionDateLabel(ref.watch(devotionTodayProvider));
    final names = ref.watch(bookNameCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('年度灵修')),
      body: Column(
        children: [
          const DevotionSyncStatus(),
          Expanded(
            child: manifest.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('无法读取日程，请重试同步')),
              data: (value) {
                if (value == null) {
                  return const Center(
                    child: Text(
                      '尚未缓存灵修日程\n联网同步后可离线阅读',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final days = value.years.expand((year) => year.days).toList()
                  ..sort((a, b) => a.date.compareTo(b.date));
                final hasToday = days.any(
                  (day) => devotionDateLabel(day.date) == today,
                );
                if (hasToday && !_positioned) {
                  _positioned = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final target = _todayKey.currentContext;
                    if (mounted && !_userScrolled && target != null) {
                      Scrollable.ensureVisible(target, alignment: 0.1);
                    }
                  });
                }
                return NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    if (notification.direction != ScrollDirection.idle) {
                      _userScrolled = true;
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    key: const Key('devotion-schedule-list'),
                    controller: _scrollController,
                    child: Column(
                      children: [
                        if (!hasToday)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('当前年份尚无日程，请联网同步。以下为已缓存日程。'),
                          ),
                        for (final day in days)
                          Container(
                            key: devotionDateLabel(day.date) == today
                                ? _todayKey
                                : null,
                            child: ListTile(
                              key: Key(
                                'devotion-day-${devotionDateLabel(day.date)}',
                              ),
                              title: Text(devotionDateLabel(day.date)),
                              subtitle: Text(
                                day.passages
                                    .map(
                                      (passage) => devotionPassageLabel(
                                        passage,
                                        names.nameFor(
                                          passage.bookId,
                                          Localizations.localeOf(context),
                                        ),
                                      ),
                                    )
                                    .join('；'),
                              ),
                              trailing: devotionDateLabel(day.date) == today
                                  ? const Chip(label: Text('今天'))
                                  : const Icon(Icons.chevron_right),
                              onTap: () => context.push(
                                '/devotion/${devotionDateLabel(day.date)}',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

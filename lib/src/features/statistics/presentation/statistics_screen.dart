import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../app/empty_state_page.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../review/domain/ebbinghaus_models.dart';
import '../../scripture/application/scripture_providers.dart';
import '../domain/achievement.dart';
import '../domain/recitation_result.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  bool _recentExpanded = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final repository = ref.watch(planRepositoryProvider);
    final names = ref.watch(bookNameCatalogProvider);
    final locale = Localizations.localeOf(context);
    final chinese = locale.languageCode == 'zh';
    return Scaffold(
      appBar: AppBar(title: Text(localizations.statisticsTitle)),
      body: repository.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _empty(context, localizations),
        data: (repository) => FutureBuilder<_StatisticsData>(
          future: _load(repository),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final hasStatistics =
                data.results.isNotEmpty ||
                data.achievements.any((item) => item.unlockedAt != null);
            final summary = data.summary;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _EbbinghausSettingsCard(
                    repository: repository,
                    initial: data.settings,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      key: const Key('about-open'),
                      leading: const Icon(Icons.info_outline_rounded),
                      title: Text(localizations.aboutTitle),
                      onTap: () => context.go('/about'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!hasStatistics)
                    _StatisticsEmptySection(
                      message: localizations.statisticsEmpty,
                      actionLabel: localizations.browseBible,
                      onAction: () => context.go('/bible'),
                    ),
                  if (hasStatistics) ...[
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SummaryCard(
                          icon: Icons.mic_rounded,
                          text: chinese
                              ? '背诵 ${summary.totalSessions} 次'
                              : '${summary.totalSessions} sessions',
                        ),
                        _SummaryCard(
                          icon: Icons.menu_book_rounded,
                          text: chinese
                              ? '累计 ${summary.totalVerses} 节'
                              : '${summary.totalVerses} verses',
                        ),
                        _SummaryCard(
                          icon: Icons.track_changes_rounded,
                          text: chinese
                              ? '平均正确率 ${(summary.averageAccuracy * 100).round()}%'
                              : 'Average ${(summary.averageAccuracy * 100).round()}%',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      chinese ? '我的成就' : 'My achievements',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 210,
                            mainAxisExtent: 150,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: data.achievements.length,
                      itemBuilder: (context, index) =>
                          _AchievementCard(progress: data.achievements[index]),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      chinese ? '最近背诵' : 'Recent recitations',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (final result
                        in _recentExpanded
                            ? data.results
                            : data.results.take(5))
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${(result.accuracy * 100).round()}'),
                          ),
                          title: Text(
                            '${names.nameFor(result.bookId, locale)} '
                            '${result.chapter}:${result.startVerse}–${result.endVerse}',
                          ),
                          subtitle: Text(
                            chinese
                                ? '${result.mode == 'verse' ? '逐节' : '连续'} · '
                                      '${result.durationSeconds} 秒 · '
                                      '${result.phoneticCorrectCount > 0 ? '同音修正 ${result.phoneticCorrectCount} · ' : ''}'
                                      '错 ${result.incorrectCount} 漏 ${result.omittedCount} '
                                      '错序 ${result.reorderedCount}'
                                : '${result.mode} · ${result.durationSeconds}s',
                          ),
                        ),
                      ),
                    if (data.results.length > 5)
                      TextButton.icon(
                        key: const Key('toggle-recent-recitation'),
                        onPressed: () =>
                            setState(() => _recentExpanded = !_recentExpanded),
                        icon: Icon(
                          _recentExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                        label: Text(
                          chinese
                              ? (_recentExpanded ? '收起最近背诵' : '查看全部背诵')
                              : (_recentExpanded ? 'Show less' : 'Show all'),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, AppLocalizations localizations) =>
      EmptyStatePage(
        title: localizations.statisticsTitle,
        message: localizations.statisticsEmpty,
        icon: Icons.insights_outlined,
        actionLabel: localizations.browseBible,
        onAction: () => context.go('/bible'),
      );

  Future<_StatisticsData> _load(SqlitePlanRepository repository) async {
    await repository.evaluateAndUnlockAchievements(source: 'backfill');
    return _StatisticsData(
      summary: await repository.getRecitationSummary(),
      results: await repository.listRecitationResults(),
      achievements: await repository.listAchievementProgress(),
      settings: await repository.getEbbinghausSettings(),
    );
  }
}

class _EbbinghausSettingsCard extends StatefulWidget {
  const _EbbinghausSettingsCard({
    required this.repository,
    required this.initial,
  });

  final SqlitePlanRepository repository;
  final EbbinghausSettings initial;

  @override
  State<_EbbinghausSettingsCard> createState() =>
      _EbbinghausSettingsCardState();
}

class _EbbinghausSettingsCardState extends State<_EbbinghausSettingsCard> {
  late bool _enabled;
  late double _threshold;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initial.enabled;
    _threshold = widget.initial.passThreshold;
  }

  Future<void> _save() => widget.repository.updateEbbinghausSettings(
    enabled: _enabled,
    passThreshold: _threshold,
  );

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final percent = (_threshold * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: const Key('ebbinghaus-toggle'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.auto_awesome_rounded),
              title: Text(chinese ? '艾宾浩斯背诵法' : 'Ebbinghaus review'),
              subtitle: Text(
                chinese
                    ? '按遗忘曲线自动安排已通过章节的复习'
                    : 'Schedule passed chapters along the forgetting curve',
              ),
              value: _enabled,
              onChanged: (value) async {
                setState(() => _enabled = value);
                await _save();
              },
            ),
            Text(
              chinese ? '通过阈值 $percent%' : 'Pass threshold $percent%',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Slider(
              key: const Key('ebbinghaus-threshold'),
              value: _threshold,
              min: 0.5,
              max: 1,
              divisions: 50,
              label: '$percent%',
              onChanged: (value) => setState(() => _threshold = value),
              onChangeEnd: (_) => _save(),
            ),
            Text(
              chinese
                  ? '复习间隔：1、2、4、7、15、30 天'
                  : 'Review after 1, 2, 4, 7, 15, and 30 days',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsEmptySection extends StatelessWidget {
  const _StatisticsEmptySection({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.insights_outlined, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.progress});

  final AchievementProgress progress;

  @override
  Widget build(BuildContext context) {
    final unlocked = progress.unlockedAt != null;
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: Key(
        'achievement-${progress.definition.id}-${unlocked ? 'unlocked' : 'locked'}',
      ),
      color: unlocked ? const Color(0xFFE8F1E9) : colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  unlocked
                      ? Icons.workspace_premium_rounded
                      : Icons.lock_outline,
                  color: unlocked ? const Color(0xFFB88A22) : colors.outline,
                ),
                const Spacer(),
                Text(
                  unlocked ? '已获得' : '${(progress.fraction * 100).round()}%',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              progress.definition.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: unlocked
                    ? const Color(0xFF24523A)
                    : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              progress.definition.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            LinearProgressIndicator(
              value: progress.fraction,
              color: unlocked ? const Color(0xFFB88A22) : colors.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon), const SizedBox(width: 8), Text(text)],
      ),
    ),
  );
}

final class _StatisticsData {
  const _StatisticsData({
    required this.summary,
    required this.results,
    required this.achievements,
    required this.settings,
  });
  final RecitationSummary summary;
  final List<RecitationResult> results;
  final List<AchievementProgress> achievements;
  final EbbinghausSettings settings;
}

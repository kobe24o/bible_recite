import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../app/empty_state_page.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../reminder/daily_task_reminder.dart';
import '../../reminder/reminder_providers.dart';
import '../../review/domain/ebbinghaus_models.dart';
import '../domain/achievement.dart';
import '../domain/recitation_result.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  final GlobalKey _shareQrKey = GlobalKey();

  static const _androidDownloadUrl =
      'https://ghfast.top/https://github.com/kobe24o/bible_recite/releases/latest/download/BibleRecite-latest.apk';
  static const _qrImageStoreChannel = MethodChannel(
    'app.biblerecite/qr_image_store',
  );

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    ref.watch(recitationDataRevisionProvider);
    final repository = ref.watch(planRepositoryProvider);
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
                  _DailyReminderCard(repository: repository),
                  const SizedBox(height: 12),
                  Card(
                    child: SwitchListTile(
                      key: const Key('ignore-final-nasal-toggle'),
                      secondary: const Icon(Icons.record_voice_over_outlined),
                      title: Text(chinese ? '忽略后鼻音' : 'Ignore final nasal'),
                      subtitle: Text(
                        chinese
                            ? '拼音纠正时将 yin / ying 等视为相同'
                            : 'Treat yin and ying as equal in phonetic scoring',
                      ),
                      value: data.ignoreFinalNasal,
                      onChanged: (value) async {
                        await repository.setSetting(
                          'ignore_final_nasal',
                          value ? 'true' : 'false',
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      key: const Key('recitation-timeline-open'),
                      leading: const Icon(Icons.timeline_rounded),
                      title: Text(chinese ? '学习轨迹' : 'Learning timeline'),
                      subtitle: Text(
                        chinese ? '按周、月、季、年回顾背诵' : 'Review practice over time',
                      ),
                      onTap: () => context.push('/statistics/timeline'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      key: const Key('recitation-map-open'),
                      leading: const Icon(Icons.map_outlined),
                      title: Text(chinese ? '背诵地图' : 'Recitation map'),
                      subtitle: Text(
                        chinese
                            ? '按卷、章、节查看进度和质量'
                            : 'Explore progress by book, chapter and verse',
                      ),
                      onTap: () => context.push('/statistics/map'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      key: const Key('share-app-button'),
                      leading: const Icon(Icons.share_outlined),
                      title: Text(chinese ? '分享应用' : 'Share app'),
                      subtitle: Text(
                        chinese ? '生成下载二维码' : 'Generate a download QR code',
                      ),
                      onTap: _showSharePlatforms,
                    ),
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
      ignoreFinalNasal:
          await repository.getSetting('ignore_final_nasal', 'true') == 'true',
    );
  }

  Future<void> _showSharePlatforms() async {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('share-android'),
              leading: const Icon(Icons.android_rounded),
              title: const Text('Android'),
              subtitle: Text(chinese ? '获取最新版安装包' : 'Get the latest APK'),
              onTap: () {
                Navigator.pop(context);
                _showAndroidQr();
              },
            ),
            const ListTile(
              leading: Icon(Icons.phone_iphone_outlined),
              title: Text('iOS'),
              subtitle: Text('即将支持'),
              enabled: false,
            ),
            const ListTile(
              leading: Icon(Icons.devices_other_outlined),
              title: Text('鸿蒙'),
              subtitle: Text('即将支持'),
              enabled: false,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showAndroidQr() async {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(chinese ? 'Android 下载二维码' : 'Android download QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              key: _shareQrKey,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: _androidDownloadUrl,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  errorStateBuilder: (_, error) => SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(child: Text('二维码生成失败：$error')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              chinese
                  ? '扫码下载最新版 Android 安装包'
                  : 'Scan to download the latest Android APK',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saveQr,
            child: Text(chinese ? '保存二维码' : 'Save QR code'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(chinese ? '完成' : 'Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveQr() async {
    try {
      final boundary =
          _shareQrKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      if (!Platform.isAndroid) {
        throw UnsupportedError('当前平台暂不支持保存二维码');
      }
      await _qrImageStoreChannel.invokeMethod<String>('savePng', {
        'bytes': Uint8List.fromList(data.buffer.asUint8List()),
        'displayName': 'BibleRecite-Android-QR.png',
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('二维码已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存二维码失败：$error')));
      }
    }
  }
}

class _DailyReminderCard extends ConsumerStatefulWidget {
  const _DailyReminderCard({required this.repository});

  final SqlitePlanRepository repository;

  @override
  ConsumerState<_DailyReminderCard> createState() => _DailyReminderCardState();
}

class _DailyReminderCardState extends ConsumerState<_DailyReminderCard> {
  late Future<DailyTaskReminderSettings> _future;

  @override
  void initState() {
    super.initState();
    _future = DailyTaskReminderScheduler.readSettings(widget.repository);
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<DailyTaskReminderSettings>(
    future: _future,
    builder: (context, snapshot) {
      final settings = snapshot.data;
      if (settings == null) return const Card(child: LinearProgressIndicator());
      return Card(
        child: Column(
          children: [
            SwitchListTile(
              key: const Key('daily-reminder-toggle'),
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('今日任务提醒'),
              subtitle: const Text('未完成今日任务时，在设定时段内重复提醒'),
              value: settings.enabled,
              onChanged: (value) => _save(settings.copyWith(enabled: value)),
            ),
            ListTile(
              enabled: settings.enabled,
              title: const Text('开始提醒时间'),
              subtitle: Text(_format(settings.startMinutes)),
              trailing: const Icon(Icons.schedule_outlined),
              onTap: () => _pickTime(settings, true),
            ),
            ListTile(
              enabled: settings.enabled,
              title: const Text('结束提醒时间'),
              subtitle: Text('${_format(settings.endMinutes)}（默认 23:59）'),
              trailing: const Icon(Icons.event_available_outlined),
              onTap: () => _pickTime(settings, false),
            ),
            ListTile(
              enabled: settings.enabled,
              title: const Text('提醒间隔'),
              subtitle: Text(_formatInterval(settings.intervalMinutes)),
              trailing: const Icon(Icons.tune_rounded),
              onTap: settings.enabled ? () => _pickInterval(settings) : null,
            ),
          ],
        ),
      );
    },
  );

  Future<void> _pickTime(DailyTaskReminderSettings settings, bool start) async {
    final minutes = start ? settings.startMinutes : settings.endMinutes;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (selected == null) return;
    final value = selected.hour * 60 + selected.minute;
    await _save(
      start
          ? settings.copyWith(startMinutes: value)
          : settings.copyWith(endMinutes: value),
    );
  }

  Future<void> _pickInterval(DailyTaskReminderSettings settings) async {
    var hours = settings.intervalMinutes ~/ 60;
    var minutes = settings.intervalMinutes % 60;
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                const ListTile(title: Text('提醒间隔')),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _wheel(
                          13,
                          hours,
                          '小时',
                          (value) => setModalState(() => hours = value),
                        ),
                      ),
                      Expanded(
                        child: _wheel(
                          60,
                          minutes,
                          '分钟',
                          (value) => setModalState(() => minutes = value),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: hours == 0 && minutes == 0
                      ? null
                      : () => Navigator.pop(context, hours * 60 + minutes),
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null)
      await _save(settings.copyWith(intervalMinutes: selected));
  }

  Widget _wheel(
    int count,
    int initial,
    String unit,
    ValueChanged<int> onChanged,
  ) => ListWheelScrollView.useDelegate(
    controller: FixedExtentScrollController(initialItem: initial),
    itemExtent: 42,
    physics: const FixedExtentScrollPhysics(),
    onSelectedItemChanged: onChanged,
    childDelegate: ListWheelChildBuilderDelegate(
      childCount: count,
      builder: (_, index) => Center(child: Text('$index $unit')),
    ),
  );

  Future<void> _save(DailyTaskReminderSettings settings) async {
    if (settings.endMinutes < settings.startMinutes) return;
    await DailyTaskReminderScheduler.saveSettings(widget.repository, settings);
    await ref
        .read(dailyTaskReminderSchedulerProvider)
        .reschedule(widget.repository);
    if (mounted) setState(() => _future = Future.value(settings));
  }

  String _format(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  String _formatInterval(int minutes) => minutes % 60 == 0
      ? '${minutes ~/ 60} 小时'
      : '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
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
    required this.ignoreFinalNasal,
  });
  final RecitationSummary summary;
  final List<RecitationResult> results;
  final List<AchievementProgress> achievements;
  final EbbinghausSettings settings;
  final bool ignoreFinalNasal;
}

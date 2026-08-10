import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../app/empty_state_page.dart';
import '../../plans/application/plan_providers.dart';
import '../../plans/data/sqlite_plan_repository.dart';
import '../../quiz/domain/quiz_result.dart';
import '../../quiz/domain/quiz_bank_exchange.dart';
import '../../quiz/application/quiz_bank_sync.dart';
import '../../quiz/application/quiz_providers.dart';
import '../../quiz/presentation/quiz_model_settings_card.dart';
import '../../reminder/daily_task_reminder.dart';
import '../../reminder/reminder_providers.dart';
import '../../review/domain/ebbinghaus_models.dart';
import '../../scripture/application/scripture_providers.dart';
import '../../scripture/data/sqlite_scripture_repository.dart';
import '../../scripture/domain/scripture_models.dart';
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
    final name = ref.watch(profileNameProvider).asData?.value ?? '';
    final repository = ref.watch(planRepositoryProvider);
    final locale = Localizations.localeOf(context);
    final chinese = locale.languageCode == 'zh';
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? localizations.statisticsTitle : name),
      ),
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
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '把神的话，藏在心里',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '一款帮助弟兄姐妹持续背诵、默想、应用神话语的圣经背诵 App',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 14),
                          RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                    fontStyle: FontStyle.italic,
                                  ),
                              children: [
                                const TextSpan(text: '“'),
                                TextSpan(
                                  text: name.isEmpty ? '我' : name,
                                  style: name.isEmpty
                                      ? null
                                      : const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                ),
                                const TextSpan(text: '将你的话藏在心里，免得'),
                                TextSpan(
                                  text: name.isEmpty ? '我' : name,
                                  style: name.isEmpty
                                      ? null
                                      : const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                ),
                                const TextSpan(text: '得罪你。”\n（诗篇119:11）'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: const Text('我的名字'),
                      subtitle: Text(name.isEmpty ? '未填写' : name),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editProfileName(name),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_stories_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              chinese
                                  ? '我们一起朗读背诵${_formatDuration(DateTime.now().difference(data.firstOpenedAt), includeSeconds: false)}了'
                                  : 'Reading together for ${_formatDuration(DateTime.now().difference(data.firstOpenedAt), includeSeconds: false)}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                          icon: Icons.timer_outlined,
                          text: chinese
                              ? '背诵总时长 ${_formatDuration(Duration(seconds: summary.totalSeconds))}'
                              : 'Total ${_formatDuration(Duration(seconds: summary.totalSeconds))}',
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
                              ? '背诵正确率 ${(summary.averageAccuracy * 100).round()}%'
                              : 'Average ${(summary.averageAccuracy * 100).round()}%',
                        ),
                        _SummaryCard(
                          icon: Icons.local_fire_department_rounded,
                          text: chinese
                              ? '目前连续背诵 ${data.learning.currentDayStreak} 天 · 最高连续背诵 ${data.learning.maxDayStreak} 天'
                              : 'Current ${data.learning.currentDayStreak} days · Best ${data.learning.maxDayStreak} days',
                        ),
                        _SummaryCard(
                          icon: Icons.format_list_numbered_rounded,
                          text: chinese
                              ? '目前连续背诵 ${data.learning.currentVerseStreak} 节 · 最高连续背诵 ${data.learning.maxVerseStreak} 节'
                              : 'Current ${data.learning.currentVerseStreak} verses · Best ${data.learning.maxVerseStreak} verses',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SummaryCard(
                        icon: Icons.quiz_outlined,
                        text: chinese
                            ? '答题 ${data.quiz.totalAnswered} 道'
                            : '${data.quiz.totalAnswered} quizzes',
                      ),
                      _SummaryCard(
                        icon: Icons.check_circle_outline_rounded,
                        text: chinese
                            ? '答对 ${data.quiz.totalCorrect} 道'
                            : '${data.quiz.totalCorrect} correct',
                      ),
                      _SummaryCard(
                        icon: Icons.track_changes_rounded,
                        text: chinese
                            ? '答题正确率 ${(data.quiz.accuracy * 100).round()}%'
                            : 'Quiz ${(data.quiz.accuracy * 100).round()}%',
                      ),
                      _SummaryCard(
                        icon: Icons.local_fire_department_outlined,
                        text: chinese
                            ? '最大连续答对 ${data.quiz.maxCorrectStreak} 道'
                            : 'Best ${data.quiz.maxCorrectStreak} correct',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _EbbinghausSettingsCard(
                    repository: repository,
                    initial: data.settings,
                  ),
                  const SizedBox(height: 12),
                  QuizModelSettingsCard(repository: repository),
                  const SizedBox(height: 12),
                  _QuizBankCard(repository: repository),
                  const SizedBox(height: 12),
                  _DailyReminderCard(repository: repository),
                  const SizedBox(height: 12),
                  Card(
                    child: SwitchListTile(
                      key: const Key('show-recitation-scripture-toggle'),
                      secondary: const Icon(Icons.visibility_outlined),
                      title: Text(
                        chinese
                            ? '开始背诵后显示原文'
                            : 'Show scripture after recording starts',
                      ),
                      subtitle: Text(
                        chinese
                            ? '进入页面时始终显示；开始录音后按此设置，仍可随时切换'
                            : 'Always shown on entry; applied when recording starts and can still be toggled',
                      ),
                      value: data.showRecitationScripture,
                      onChanged: (value) async {
                        await repository.setSetting(
                          'show_recitation_scripture',
                          value ? 'true' : 'false',
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
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
                    Text(
                      chinese
                          ? (name.isEmpty ? '我的成就' : '$name的成就')
                          : (name.isEmpty
                                ? 'My achievements'
                                : "$name's achievements"),
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
                      itemBuilder: (context, index) => _AchievementCard(
                        progress: data.achievements[index],
                        onTap: () => _showAchievement(data.achievements[index]),
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

  Future<void> _editProfileName(String current) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('我的名字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '留空则显示“我的”'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final repository = await ref.read(planRepositoryProvider.future);
    await repository.setSetting('profile_name', value);
    ref.read(profileRevisionProvider.notifier).refresh();
  }

  Future<_StatisticsData> _load(SqlitePlanRepository repository) async {
    await repository.evaluateAndUnlockAchievements(source: 'backfill');
    final coverage = await _coverageAchievements(repository);
    return _StatisticsData(
      summary: await repository.getRecitationSummary(),
      quiz: await repository.getQuizSummary(),
      learning: await repository.getLearningStats(),
      results: await repository.listRecitationResults(),
      achievements: [
        ...await repository.listAchievementProgress(),
        ...coverage,
      ],
      settings: await repository.getEbbinghausSettings(),
      ignoreFinalNasal:
          await repository.getSetting('ignore_final_nasal', 'true') == 'true',
      showRecitationScripture:
          await repository.getSetting('show_recitation_scripture', 'true') ==
          'true',
      firstOpenedAt: await repository.getFirstOpenedAt(),
    );
  }

  Future<List<AchievementProgress>> _coverageAchievements(
    SqlitePlanRepository repository,
  ) async {
    final metrics = await repository.listRecitationVerseMetrics();
    if (metrics.isEmpty) return const [];
    final scripture = await ref.read(scriptureRepositoryProvider.future);
    final books = await scripture.listBooks('cmn-cu89s', CanonId.protestant66);
    final names = ref.read(bookNameCatalogProvider);
    final chapterTotals = scripture is SqliteScriptureRepository
        ? await scripture.getChapterVerseCounts('cmn-cu89s')
        : <String, int>{
            for (final book in books)
              for (var chapter = 1; chapter <= book.chapterCount; chapter++)
                '${book.osisId}:$chapter': (await scripture.getChapter(
                  'cmn-cu89s',
                  book.osisId,
                  chapter,
                )).length,
          };
    final covered = <String, Set<int>>{};
    for (final item in metrics) {
      covered
          .putIfAbsent('${item.bookId}:${item.chapter}', () => <int>{})
          .add(item.verse);
    }
    final definitions = <AchievementDefinition>[];
    final satisfied = <String>{};
    final currentValues = <String, double>{};
    final plans = await repository.listPlans();
    for (final plan in plans.where((plan) => plan.sourceKind.name == 'cloud')) {
      final id = 'preset_plan_${plan.externalId ?? plan.id}';
      definitions.add(
        AchievementDefinition(
          id: id,
          title: '${plan.title}勋章',
          description: '完成预置计划《${plan.title}》',
          metric: AchievementMetric.sessions,
          target: 1,
        ),
      );
      if (plan.totalTasks > 0 && plan.completedTasks == plan.totalTasks) {
        satisfied.add(id);
      }
      currentValues[id] = plan.totalTasks == 0
          ? 0
          : plan.completedTasks / plan.totalTasks;
    }
    var oldCovered = 0;
    var oldTotal = 0;
    var newCovered = 0;
    var newTotal = 0;
    for (final book in books) {
      final id = 'book_complete_${book.osisId}';
      definitions.add(
        AchievementDefinition(
          id: id,
          title: '${names.nameFor(book.osisId, const Locale('zh', 'CN'))}勋章',
          description:
              '完成${names.nameFor(book.osisId, const Locale('zh', 'CN'))}全部经文',
          metric: AchievementMetric.sessions,
          target: 1,
        ),
      );
      var bookCovered = 0;
      var bookTotal = 0;
      for (var chapter = 1; chapter <= book.chapterCount; chapter++) {
        final key = '${book.osisId}:$chapter';
        final total = chapterTotals[key] ?? 0;
        bookTotal += total;
        bookCovered += (covered[key]?.length ?? 0).clamp(0, total).toInt();
      }
      final fraction = bookTotal == 0 ? 0.0 : bookCovered / bookTotal;
      currentValues[id] = fraction;
      if (fraction >= 1) satisfied.add(id);
      if (book.ordinal <= 39) {
        oldCovered += bookCovered;
        oldTotal += bookTotal;
      } else {
        newCovered += bookCovered;
        newTotal += bookTotal;
      }
    }
    final scopeProgress = <String, double>{
      'old_testament_complete': oldTotal == 0 ? 0 : oldCovered / oldTotal,
      'new_testament_complete': newTotal == 0 ? 0 : newCovered / newTotal,
      'bible_complete': oldTotal + newTotal == 0
          ? 0
          : (oldCovered + newCovered) / (oldTotal + newTotal),
    };
    for (final entry in <({String id, String title, String description})>[
      (id: 'old_testament_complete', title: '旧约勋章', description: '完成旧约全部经文'),
      (id: 'new_testament_complete', title: '新约勋章', description: '完成新约全部经文'),
      (id: 'bible_complete', title: '圣经勋章', description: '完成整本圣经全部经文'),
    ]) {
      definitions.add(
        AchievementDefinition(
          id: entry.id,
          title: entry.title,
          description: entry.description,
          metric: AchievementMetric.sessions,
          target: 1,
        ),
      );
      currentValues[entry.id] = scopeProgress[entry.id]!;
      if (scopeProgress[entry.id]! >= 1) satisfied.add(entry.id);
    }
    return repository.syncExternalAchievements(
      definitions,
      satisfied,
      currentValues,
    );
  }

  Future<void> _showAchievement(
    AchievementProgress progress,
  ) => showDialog<void>(
    context: context,
    builder: (context) {
      final unlocked = progress.unlockedAt != null;
      return AlertDialog(
        icon: Icon(
          unlocked ? Icons.workspace_premium_rounded : Icons.lock_outline,
        ),
        title: Text(progress.definition.title),
        content: Text(
          '${progress.definition.description}\n\n'
          '当前进度：${(progress.fraction * 100).round()}%\n'
          '${unlocked ? '获得状态：已获得\n获得时间：${_formatDateTime(progress.unlockedAt!)}' : '获得状态：尚未获得'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );

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

class _QuizBankCard extends ConsumerStatefulWidget {
  const _QuizBankCard({required this.repository});

  final SqlitePlanRepository repository;

  @override
  ConsumerState<_QuizBankCard> createState() => _QuizBankCardState();
}

class _QuizBankCardState extends ConsumerState<_QuizBankCard> {
  static const _jsonStoreChannel = MethodChannel(
    'app.biblerecite/plan_json_store',
  );
  late Future<QuizBankSyncStatus> _status;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _status = loadQuizBankSyncStatus(widget.repository);
  }

  @override
  Widget build(BuildContext context) => Card(
    child: FutureBuilder<QuizBankSyncStatus>(
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final subtitle = status == null
            ? '正在读取题库状态'
            : '${status.lastStatus}${status.lastSyncedAt == null ? '' : ' · ${_formatTime(status.lastSyncedAt!)}'}';
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.quiz_outlined),
              title: const Text('共享答题题库'),
              subtitle: Text(subtitle),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '启动时先检查小索引；题库未变化不会下载。同步、导入只增加题目，不会上传答题记录或模型密钥。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  key: const Key('quiz-bank-import'),
                  onPressed: _working ? null : _import,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('导入'),
                ),
                TextButton.icon(
                  key: const Key('quiz-bank-export'),
                  onPressed: _working ? null : _export,
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('导出'),
                ),
                FilledButton.icon(
                  key: const Key('quiz-bank-sync'),
                  onPressed: _working ? null : _sync,
                  icon: _working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: const Text('同步题库'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    ),
  );

  Future<void> _sync() async {
    setState(() => _working = true);
    try {
      final result = await syncQuizBank(
        repository: widget.repository,
        client: ref.read(quizBankFeedClientProvider),
      );
      if (!mounted) return;
      ref.read(profileRevisionProvider.notifier).refresh();
      setState(() => _status = loadQuizBankSyncStatus(widget.repository));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.upToDate
                ? '题库已是最新'
                : '题库同步完成：新增 ${result.imported} 道，重复 ${result.duplicates} 道',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('题库同步失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _export() async {
    try {
      final source = QuizBankExchange.encode(
        await widget.repository.listQuizBankQuestions(),
      );
      final bytes = utf8.encode(source);
      const name = 'BibleRecite-quiz-bank.json';
      if (Platform.isAndroid) {
        await _jsonStoreChannel.invokeMethod<String>('saveJson', {
          'bytes': bytes,
          'displayName': name,
        });
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'JSON',
              extensions: ['json'],
              mimeTypes: ['application/json'],
            ),
          ],
        );
        if (location == null) return;
        await XFile.fromData(
          bytes,
          mimeType: 'application/json',
          name: name,
        ).saveTo(location.path);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('答题题库已导出（不含答题记录和模型密钥）')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出题库失败：$error')));
      }
    }
  }

  Future<void> _import() async {
    const jsonType = XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      mimeTypes: ['application/json'],
      uniformTypeIdentifiers: ['public.json', 'public.text'],
      webWildCards: ['application/json'],
    );
    final selected = await openFile(acceptedTypeGroups: const [jsonType]);
    if (selected == null) return;
    setState(() => _working = true);
    try {
      final bytes = await selected.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('题库 JSON 文件不能超过 10 MB');
      }
      final result = await widget.repository.importQuizBankQuestions(
        QuizBankExchange.decode(utf8.decode(bytes)),
      );
      if (!mounted) return;
      ref.read(profileRevisionProvider.notifier).refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${result.imported} 道题目，重复 ${result.duplicates} 道；新题均为未作答',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导入题库失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _formatTime(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
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
    if (selected != null) {
      await _save(settings.copyWith(intervalMinutes: selected));
    }
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
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome_rounded),
              title: Text(chinese ? '艾宾浩斯背诵法' : 'Ebbinghaus review settings'),
              subtitle: Text(
                chinese
                    ? '请在每个背诵计划内单独开启；此处仅设置通过阈值'
                    : 'Enable it per memorization plan; set only the pass threshold here.',
              ),
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

String _formatDuration(Duration duration, {bool includeSeconds = true}) {
  var seconds = duration.inSeconds.clamp(0, 1 << 62);
  final years = seconds ~/ (365 * 24 * 3600);
  seconds -= years * 365 * 24 * 3600;
  final days = seconds ~/ (24 * 3600);
  seconds -= days * 24 * 3600;
  final hours = seconds ~/ 3600;
  seconds -= hours * 3600;
  final minutes = seconds ~/ 60;
  seconds -= minutes * 60;
  final parts = <String>[
    if (years > 0) '$years年',
    if (days > 0) '$days天',
    if (hours > 0) '$hours小时',
    if (minutes > 0) '$minutes分钟',
    if (includeSeconds && seconds > 0) '$seconds秒',
  ];
  return parts.isEmpty ? '0秒' : parts.join();
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.progress, required this.onTap});

  final AchievementProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = progress.unlockedAt != null;
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: Key(
        'achievement-${progress.definition.id}-${unlocked ? 'unlocked' : 'locked'}',
      ),
      color: unlocked ? const Color(0xFFE8F1E9) : colors.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                    unlocked
                        ? '已获得 · ${(progress.fraction * 100).round()}%'
                        : '${(progress.fraction * 100).round()}%',
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
    required this.quiz,
    required this.learning,
    required this.results,
    required this.achievements,
    required this.settings,
    required this.ignoreFinalNasal,
    required this.showRecitationScripture,
    required this.firstOpenedAt,
  });
  final RecitationSummary summary;
  final QuizSummary quiz;
  final LearningStats learning;
  final List<RecitationResult> results;
  final List<AchievementProgress> achievements;
  final EbbinghausSettings settings;
  final bool ignoreFinalNasal;
  final bool showRecitationScripture;
  final DateTime firstOpenedAt;
}

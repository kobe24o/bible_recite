import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../scripture/application/scripture_providers.dart';
import '../../scripture/domain/scripture_models.dart';
import '../../scripture/domain/scripture_repository.dart';
import '../../scripture/domain/book_name_catalog.dart';
import '../../recitation/application/plan_recitation_builder.dart';
import '../../recitation/presentation/recitation_practice_screen.dart';
import '../../quiz/domain/quiz_scope.dart';
import '../../reminder/reminder_providers.dart';
import '../../review/domain/ebbinghaus_models.dart';
import '../application/plan_providers.dart';
import '../application/preset_plan_sync.dart';
import '../data/sqlite_plan_repository.dart';
import '../domain/cloud_plan_manifest.dart';
import '../domain/plan_draft_builder.dart';
import '../domain/plan_exchange.dart';
import '../domain/plan_models.dart';
import 'plan_editor_dialog.dart';

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

final class _PresetPlansData {
  const _PresetPlansData({required this.manifest, required this.newPlanIds});

  final CloudPlanManifest manifest;
  final Set<String> newPlanIds;
}

final class _PlansData {
  const _PlansData({required this.plans, required this.tasksByPlan});

  final List<MemorizationPlan> plans;
  final Map<int, List<PlanTask>> tasksByPlan;
}

class _NewPlanBadge extends StatelessWidget {
  const _NewPlanBadge();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 8),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      'NEW',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onError,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

enum _PlanAction { export, edit, restart, pause, resume }

class _PlansScreenState extends ConsumerState<PlansScreen> {
  static const _planJsonStoreChannel = MethodChannel(
    'app.biblerecite/plan_json_store',
  );
  int _revision = 0;
  bool _working = false;
  Future<_PresetPlansData>? _presetPlansFuture;
  int? _presetPlansFutureRevision;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final recitationRevision = ref.watch(recitationDataRevisionProvider);
    final presetRevision = ref.watch(presetPlanRevisionProvider);
    final repository = ref.watch(planRepositoryProvider);
    final bundled = ref.watch(bundledCloudPlanManifestProvider);
    return Scaffold(
      appBar: AppBar(title: Text(localizations.plansTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_working) const LinearProgressIndicator(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('cloud-plan-source-button'),
                  onPressed: _working ? null : _editCloudSource,
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('云端来源'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('sync-cloud-plans-button'),
                  onPressed: _working ? null : _syncCloudPlans,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('同步计划'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('import-cloud-plan-file-button'),
            onPressed: _working ? null : _importCloudPlanFile,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('从 JSON 文件导入'),
          ),
          const SizedBox(height: 18),
          repository.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (repository) => FutureBuilder<_PlansData>(
              key: ValueKey('$_revision-$recitationRevision'),
              future: _loadPlans(repository),
              builder: (context, snapshot) {
                final planData = snapshot.data;
                final plans = planData?.plans ?? const <MemorizationPlan>[];
                if (plans.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '我的背诵计划',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (final plan in plans)
                      _planCard(
                        plan,
                        localizations,
                        planData?.tasksByPlan[plan.id] ?? const [],
                      ),
                    const SizedBox(height: 18),
                    Text(
                      '我的复习计划（艾宾浩斯）',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (!plans.any((plan) => plan.ebbinghausEnabled))
                      const Text('尚未为背诵计划开启艾宾浩斯复习')
                    else
                      for (final plan in plans.where(
                        (plan) => plan.ebbinghausEnabled,
                      ))
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.repeat_rounded),
                            ),
                            title: Text(plan.title),
                            subtitle: Text(plan.paused ? '已暂停' : '复习计划已开启'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: _working
                                ? null
                                : () => _showReviewPlan(plan),
                          ),
                        ),
                    const SizedBox(height: 18),
                  ],
                );
              },
            ),
          ),
          Text(
            localizations.presetPlans,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          bundled.when(
            loading: () => const Text('正在加载预置计划…'),
            error: (error, _) => Text('无法加载预置计划：$error'),
            data: (bundledManifest) => presetRevision == 0
                ? _presetPlanList(
                    _PresetPlansData(
                      manifest: bundledManifest,
                      newPlanIds: const <String>{},
                    ),
                  )
                : repository.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (repository) {
                      if (_presetPlansFuture == null ||
                          _presetPlansFutureRevision != presetRevision) {
                        _presetPlansFuture = _loadPresetPlans(
                          repository,
                          bundledManifest,
                        );
                        _presetPlansFutureRevision = presetRevision;
                      }
                      return FutureBuilder<_PresetPlansData>(
                        key: ValueKey(presetRevision),
                        future: _presetPlansFuture,
                        builder: (context, snapshot) => snapshot.hasData
                            ? _presetPlanList(snapshot.data!)
                            : const SizedBox.shrink(),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _working ? null : _createCustomPlan,
            icon: const Icon(Icons.tune_rounded),
            label: Text(localizations.customPlan),
          ),
        ],
      ),
    );
  }

  Future<_PlansData> _loadPlans(SqlitePlanRepository repository) async {
    final plans = await repository.listPlans();
    final taskLists = await Future.wait([
      for (final plan in plans) repository.listTasks(plan.id),
    ]);
    return _PlansData(
      plans: plans,
      tasksByPlan: {
        for (var index = 0; index < plans.length; index++)
          plans[index].id: taskLists[index],
      },
    );
  }

  Future<_PresetPlansData> _loadPresetPlans(
    SqlitePlanRepository repository,
    CloudPlanManifest bundled,
  ) async => _PresetPlansData(
    manifest: await loadCachedPresetPlanManifest(repository) ?? bundled,
    newPlanIds: await loadNewPresetPlanIds(repository),
  );

  Widget _presetPlanList(_PresetPlansData data) => Column(
    children: [
      for (final template in data.manifest.plans)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.auto_stories_outlined),
              ),
              title: Row(
                children: [
                  Expanded(child: Text(template.title)),
                  if (data.newPlanIds.contains(template.id))
                    const _NewPlanBadge(),
                ],
              ),
              subtitle: SizedBox(
                height: 40,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    '${template.description} · ${template.passages.length} 段经文',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _working ? null : () => _openPresetPlan(template),
            ),
          ),
        ),
    ],
  );

  Future<void> _openPresetPlan(CloudPlanTemplate template) async {
    final repository = await ref.read(planRepositoryProvider.future);
    await markPresetPlanSeen(repository, template.id);
    ref.read(presetPlanRevisionProvider.notifier).refresh();
    if (!mounted) return;
    await _showPresetPlanDetail(template);
  }

  Future<void> _showPresetPlanDetail(CloudPlanTemplate template) async {
    final catalog = ref.read(bookNameCatalogProvider);
    final locale = Localizations.localeOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .82,
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                Text(
                  template.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (template.tag.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Chip(label: Text(template.tag)),
                ],
                if (template.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(template.description),
                ],
                const SizedBox(height: 20),
                Text('经文列表', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final passage in template.passages)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${passage.order}')),
                    title: Text(_passageLabel(passage, catalog, locale)),
                  ),
              ],
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton.icon(
                key: const Key('add-preset-plan-button'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _configureTemplate(template);
                },
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text('添加到我的计划'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _passageLabel(
    CloudPlanPassage passage,
    BookNameCatalog catalog,
    Locale locale,
  ) {
    final start = '${passage.startChapter}:${passage.startVerse}';
    final end = '${passage.endChapter}:${passage.endVerse}';
    return '${catalog.nameFor(passage.bookId, locale)} $start–$end';
  }

  Future<void> _showReviewPlan(MemorizationPlan plan) async {
    final repository = await ref.read(planRepositoryProvider.future);
    final reviews = await repository.listEbbinghausReviewsForPlan(plan.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              '${plan.title} · 艾宾浩斯复习',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(plan.paused ? '该复习计划已暂停' : '复习计划进行中'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                if (plan.paused) {
                  await repository.resumePlan(plan.id);
                } else {
                  await repository.pausePlan(plan.id);
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                setState(() => _revision++);
              },
              icon: Icon(
                plan.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
              label: Text(plan.paused ? '继续复习计划' : '暂停复习计划'),
            ),
            if (plan.totalTasks > 0 &&
                plan.completedTasks == plan.totalTasks) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await repository.restartPlan(plan.id);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  setState(() => _revision++);
                },
                icon: const Icon(Icons.replay_rounded),
                label: const Text('再次执行背诵计划'),
              ),
            ],
            const SizedBox(height: 12),
            if (reviews.isEmpty) const Text('尚未产生复习记录'),
            for (final review in reviews)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _showReviewActions(plan, review),
                leading: CircleAvatar(child: Text('${review.intervalDays}')),
                title: Text(
                  '第 ${review.intervalDays} 天 · ${review.dueDate.year}-${review.dueDate.month.toString().padLeft(2, '0')}-${review.dueDate.day.toString().padLeft(2, '0')}',
                ),
                subtitle: Text(
                  '${review.bookId} ${review.startChapter}:${review.startVerse}–${review.endChapter}:${review.endVerse} · ${_reviewStatusLabel(review.status)}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReviewActions(
    MemorizationPlan plan,
    EbbinghausReview review,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '第 ${review.intervalDays} 天复习',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '${review.bookId} ${review.startChapter}:${review.startVerse}–${review.endChapter}:${review.endVerse}',
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('高亮阅读'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(
                  '/bible/${review.translationId}/${review.bookId}/${review.startChapter}?verse=${review.startVerse}&endVerse=${review.endVerse}',
                );
              },
            ),
            if (review.status == 'pending')
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _startReviewRecitation(plan, review);
                },
                icon: const Icon(Icons.mic_rounded),
                label: const Text('背诵这段经文'),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _startReviewRecitation(
    MemorizationPlan plan,
    EbbinghausReview review,
  ) async {
    final scripture = await ref.read(scriptureRepositoryProvider.future);
    final passage = await scripture.getPassage(
      review.translationId,
      PassageRange(
        start: (
          canonId: CanonId.protestant66,
          osisBookId: review.bookId,
          chapter: review.startChapter,
          verse: review.startVerse,
        ),
        end: (
          canonId: CanonId.protestant66,
          osisBookId: review.bookId,
          chapter: review.endChapter,
          verse: review.endVerse,
        ),
      ),
    );
    if (!mounted || passage.units.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecitationPracticeScreen(
          request: RecitationRequest(
            translationId: review.translationId,
            bookId: review.bookId,
            chapter: review.startChapter,
            mode: RecitationMode.continuous,
            units: passage.units,
            planId: plan.id,
            reviewId: review.id,
            quizScopes: [
              QuizScope(
                translationId: review.translationId,
                bookId: review.bookId,
                startChapter: review.startChapter,
                startVerse: review.startVerse,
                endChapter: review.endChapter,
                endVerse: review.endVerse,
              ),
            ],
            todayQuizEntry: true,
          ),
        ),
      ),
    );
    if (mounted) setState(() => _revision++);
  }

  String _reviewStatusLabel(String status) => switch (status) {
    'completed' => '已通过',
    'failed' => '未通过',
    'cancelled' => '已取消',
    _ => '待复习',
  };

  Widget _planCard(
    MemorizationPlan plan,
    AppLocalizations localizations,
    List<PlanTask> tasks,
  ) {
    final locked = plan.contentLocked;
    final completed =
        plan.totalTasks > 0 && plan.completedTasks == plan.totalTasks;
    final bookSummary = _planBookSummary(tasks, plan);
    final progress = plan.paused
        ? '$bookSummary · 已暂停：不再推送每日计划和艾宾浩斯复习'
        : locked
        ? '$bookSummary · ${plan.totalTasks} 段经文 · ${plan.completedTasks}/${plan.totalTasks} · '
              '${_translationLabel(plan.translationId)} · ${localizations.daysCount(plan.days)}'
        : '$bookSummary · '
              '${plan.completedTasks}/${plan.totalTasks} · '
              '${_translationLabel(plan.translationId)}';
    final statistics = plan.recitationSessions == 0
        ? '该计划尚无背诵记录'
        : '已背诵 ${plan.recitationSessions} 次 · 平均正确率 '
              '${(plan.averageAccuracy * 100).round()}% · 累计 ${_formatDuration(plan.totalRecitationSeconds)}';
    return Card(
      color: plan.paused
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: ListTile(
        leading: Icon(
          plan.sourceKind == PlanSourceKind.cloud
              ? Icons.cloud_done_outlined
              : Icons.event_available_rounded,
        ),
        title: Row(
          children: [
            Expanded(child: Text(plan.title)),
            if (plan.sourceKind == PlanSourceKind.cloud)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('云端'),
                ),
              ),
            if (plan.paused)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('已暂停'),
                ),
              ),
          ],
        ),
        subtitle: Text('$progress\n$statistics'),
        isThreeLine: true,
        subtitleTextStyle: Theme.of(context).textTheme.bodySmall,
        trailing: PopupMenuButton<_PlanAction>(
          key: Key('plan-actions-${plan.id}'),
          tooltip: '计划操作',
          onSelected: _working
              ? null
              : (action) async {
                  switch (action) {
                    case _PlanAction.export:
                      await _exportPlan(plan);
                    case _PlanAction.edit:
                      await _editPlan(plan);
                    case _PlanAction.restart:
                      await _restartPlan(plan);
                    case _PlanAction.pause:
                      await _pausePlan(plan);
                    case _PlanAction.resume:
                      await _resumePlan(plan);
                  }
                },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _PlanAction.export,
              child: ListTile(
                leading: Icon(Icons.ios_share_outlined),
                title: Text('导出计划 JSON'),
              ),
            ),
            if (!plan.paused && !completed)
              const PopupMenuItem(
                value: _PlanAction.pause,
                child: ListTile(
                  leading: Icon(Icons.pause_circle_outline_rounded),
                  title: Text('暂停计划'),
                ),
              ),
            if (plan.paused)
              const PopupMenuItem(
                value: _PlanAction.resume,
                child: ListTile(
                  leading: Icon(Icons.play_circle_outline_rounded),
                  title: Text('继续计划'),
                ),
              ),
            const PopupMenuItem(
              value: _PlanAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('编辑计划'),
              ),
            ),
            if (completed)
              const PopupMenuItem(
                value: _PlanAction.restart,
                child: ListTile(
                  leading: Icon(Icons.replay_rounded),
                  title: Text('再次执行'),
                ),
              ),
          ],
        ),
        onTap: _working ? null : () => _showPlanSchedule(plan),
      ),
    );
  }

  String _planBookSummary(List<PlanTask> tasks, MemorizationPlan plan) {
    final orderedBooks = <String>[];
    for (final task in tasks) {
      if (!orderedBooks.contains(task.bookId)) orderedBooks.add(task.bookId);
    }
    if (orderedBooks.isEmpty) orderedBooks.add(plan.bookId);
    final catalog = ref.read(bookNameCatalogProvider);
    final firstName = catalog.nameFor(
      orderedBooks.first,
      const Locale('zh', 'CN'),
    );
    return orderedBooks.length > 1 ? '$firstName等' : firstName;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return minutes == 0 ? '$remainder 秒' : '$minutes 分 $remainder 秒';
  }

  Future<void> _restartPlan(MemorizationPlan plan) async {
    await _runSave(() async {
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.restartPlan(plan.id);
    });
  }

  Future<void> _pausePlan(MemorizationPlan plan) async {
    await _runSave(() async {
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.pausePlan(plan.id);
    });
  }

  Future<void> _resumePlan(MemorizationPlan plan) async {
    await _runSave(() async {
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.resumePlan(plan.id);
    });
  }

  Future<void> _exportPlan(MemorizationPlan plan) async {
    final tasks = await (await ref.read(
      planRepositoryProvider.future,
    )).listTasks(plan.id);
    final bytes = utf8.encode(PlanExchange.encode(plan, tasks));
    final name = 'BibleRecite-${_fileName(plan.title)}.json';
    if (Platform.isAndroid) {
      await _planJsonStoreChannel.invokeMethod<String>('saveJson', {
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
        name: 'plan.json',
      ).saveTo(location.path);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('计划 JSON 已保存至 Download/BibleRecite/$name')),
    );
  }

  String _fileName(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  Future<void> _showPlanSchedule(MemorizationPlan plan) async {
    final repository = await ref.read(planRepositoryProvider.future);
    final tasks = await repository.listTasks(plan.id);
    if (!mounted) return;
    final catalog = ref.read(bookNameCatalogProvider);
    final locale = Localizations.localeOf(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(plan.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('每天背诵安排 · ${plan.days} 天'),
            const SizedBox(height: 12),
            for (final entry in _tasksByDay(tasks).entries)
              _dayScheduleGroup(
                plan: plan,
                tasks: tasks,
                dayTasks: entry.value,
                catalog: catalog,
                locale: locale,
              ),
          ],
        ),
      ),
    );
  }

  Map<int, List<PlanTask>> _tasksByDay(List<PlanTask> tasks) {
    final grouped = <int, List<PlanTask>>{};
    for (final task in tasks) {
      grouped.putIfAbsent(task.dayIndex, () => []).add(task);
    }
    return grouped;
  }

  Widget _dayScheduleGroup({
    required MemorizationPlan plan,
    required List<PlanTask> tasks,
    required List<PlanTask> dayTasks,
    required BookNameCatalog catalog,
    required Locale locale,
  }) {
    final first = dayTasks.first;
    final date = first.dueDate;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(child: Text('${first.dayIndex + 1}')),
              title: Text('第 ${first.dayIndex + 1} 天'),
              subtitle: Text(
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} · ${dayTasks.length} 段经文',
              ),
            ),
            for (final task in dayTasks)
              Dismissible(
                key: Key('plan-task-${task.id}'),
                direction: task.completed
                    ? DismissDirection.none
                    : DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                confirmDismiss: (_) => _confirmDeleteTask(plan, task),
                onDismissed: (_) => setState(() => _revision++),
                child: Stack(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.only(
                        left: 20,
                        right: task.completed ? 34 : 8,
                      ),
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(
                        '${catalog.nameFor(task.bookId, locale)} ${task.startChapter}:${task.startVerse}'
                        '${task.endChapter == task.startChapter && task.endVerse == task.startVerse ? '' : '–${task.endChapter}:${task.endVerse}'}',
                      ),
                      trailing: Wrap(
                        spacing: 2,
                        children: [
                          TextButton(
                            key: Key('read-task-${task.id}'),
                            onPressed: () {
                              context.push(
                                '/bible/${plan.translationId}/${task.bookId}/${task.startChapter}?verse=${task.startVerse}&endVerse=${task.endVerse}',
                              );
                            },
                            child: const Text('阅读'),
                          ),
                          TextButton(
                            key: Key('recite-task-${task.id}'),
                            onPressed: () async {
                              final scripture = await ref.read(
                                scriptureRepositoryProvider.future,
                              );
                              final request = await buildPlanRecitationRequest(
                                scripture: scripture,
                                plan: plan,
                                tasks: tasks,
                                selected: task,
                              );
                              if (!mounted || request == null) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RecitationPracticeScreen(
                                    request: request,
                                  ),
                                ),
                              );
                              if (mounted) setState(() => _revision++);
                            },
                            child: const Text('背诵'),
                          ),
                        ],
                      ),
                      onTap: null,
                    ),
                    if (task.completed)
                      const Positioned(
                        top: 6,
                        right: 8,
                        child: Icon(Icons.check_circle, color: Colors.green),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteTask(MemorizationPlan plan, PlanTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这项经文？'),
        content: Text('将从“${plan.title}”中删除这条未完成安排。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final repository = await ref.read(planRepositoryProvider.future);
    await repository.deleteTask(task.id);
    return true;
  }

  Future<void> _configureTemplate(CloudPlanTemplate template) async {
    final data = await _loadEditorData(
      translationId: template.defaultTranslationId,
    );
    if (!mounted || data == null) return;
    final start = template.defaultStartDate ?? _today();
    final minimumEnd = start.add(Duration(days: template.passages.length - 1));
    final configuredEnd = template.defaultEndDate;
    final end = configuredEnd == null || configuredEnd.isBefore(minimumEnd)
        ? minimumEnd
        : configuredEnd;
    final first = template.passages.first;
    final result = await showDialog<PlanEditorResult>(
      context: context,
      builder: (_) => PlanEditorDialog(
        books: data.books,
        onAddPassages: () => _pickPassages(data),
        contentLocked: true,
        minimumDays: template.passages.length,
        initial: PlanEditorDraft(
          title: template.title,
          translationId: template.defaultTranslationId,
          bookId: first.bookId,
          startChapter: first.startChapter,
          endChapter: first.endChapter,
          startDate: start,
          endDate: end,
        ),
      ),
    );
    if (result?.draft == null) return;
    await _saveTemplate(template, result!.draft!);
  }

  Future<void> _saveTemplate(
    CloudPlanTemplate template,
    PlanEditorDraft draft,
  ) async {
    final first = template.passages.first;
    final tasks = _scheduledTemplateTasks(template.passages, draft.days);
    await _runSave(() async {
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.createPlan(
        NewMemorizationPlan(
          title: template.title,
          translationId: draft.translationId,
          bookId: first.bookId,
          startChapter: first.startChapter,
          endChapter: first.endChapter,
          startDate: draft.startDate,
          endDate: draft.endDate,
          tasks: tasks,
          sourceKind: PlanSourceKind.preset,
          externalId: template.id,
          revision: template.revision,
          contentLocked: true,
        ),
      );
    });
  }

  List<NewPlanTask> _scheduledTemplateTasks(
    List<CloudPlanPassage> passages,
    int days,
  ) => [
    for (var index = 0; index < passages.length; index++)
      NewPlanTask(
        dayIndex: passages.length == 1
            ? 0
            : (index * (days - 1) / (passages.length - 1)).round(),
        bookId: passages[index].bookId,
        startChapter: passages[index].startChapter,
        startVerse: passages[index].startVerse,
        endChapter: passages[index].endChapter,
        endVerse: passages[index].endVerse,
      ),
  ];

  Future<void> _createCustomPlan() async {
    final data = await _loadEditorData();
    if (!mounted || data == null || data.books.isEmpty) return;
    final start = _today();
    final book = data.books.firstWhere(
      (item) => item.osisId == 'JHN',
      orElse: () => data.books.first,
    );
    final result = await showDialog<PlanEditorResult>(
      context: context,
      builder: (_) => PlanEditorDialog(
        books: data.books,
        onAddPassages: () => _pickPassages(data),
        initial: PlanEditorDraft(
          title: '我的背诵计划',
          translationId: data.translation.id,
          bookId: book.osisId,
          startChapter: 1,
          endChapter: 1,
          startDate: start,
          endDate: start.add(const Duration(days: 29)),
        ),
      ),
    );
    if (result?.draft != null) await _saveCustomPlan(result!.draft!);
  }

  Future<void> _editPlan(MemorizationPlan plan) async {
    final data = await _loadEditorData(translationId: plan.translationId);
    if (!mounted || data == null) return;
    final existingTasks = await (await ref.read(
      planRepositoryProvider.future,
    )).listTasks(plan.id);
    final result = await showDialog<PlanEditorResult>(
      context: context,
      builder: (_) => PlanEditorDialog(
        books: data.books,
        onAddPassages: plan.contentLocked ? null : () => _pickPassages(data),
        allowDelete: true,
        contentLocked: plan.contentLocked,
        minimumDays: plan.contentLocked ? plan.totalTasks : 1,
        initial: PlanEditorDraft(
          title: plan.title,
          translationId: plan.translationId,
          bookId: plan.bookId,
          startChapter: plan.startChapter,
          endChapter: plan.endChapter,
          startDate: plan.startDate,
          endDate: plan.endDate,
          passages: [
            for (final task in existingTasks)
              PlanPassageSelection(
                bookId: task.bookId,
                startChapter: task.startChapter,
                startVerse: task.startVerse,
                endChapter: task.endChapter,
                endVerse: task.endVerse,
              ),
          ],
          ebbinghausEnabled: plan.ebbinghausEnabled,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result.delete) {
      await _confirmDelete(plan);
    } else if (result.draft != null) {
      if (plan.contentLocked) {
        await _saveLockedPlan(plan, result.draft!);
      } else {
        await _saveCustomPlan(result.draft!, planId: plan.id);
      }
    }
  }

  Future<void> _confirmDelete(MemorizationPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除计划？'),
        content: Text('“${plan.title}”及其任务将从本机删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.deletePlan(plan.id);
      if (mounted) setState(() => _revision++);
    }
  }

  Future<void> _saveLockedPlan(
    MemorizationPlan existing,
    PlanEditorDraft draft,
  ) async {
    await _runSave(() async {
      final repository = await ref.read(planRepositoryProvider.future);
      final oldTasks = await repository.listTasks(existing.id);
      final tasks = <NewPlanTask>[
        for (var index = 0; index < oldTasks.length; index++)
          NewPlanTask(
            dayIndex: oldTasks.length == 1
                ? 0
                : (index * (draft.days - 1) / (oldTasks.length - 1)).round(),
            bookId: oldTasks[index].bookId,
            startChapter: oldTasks[index].startChapter,
            startVerse: oldTasks[index].startVerse,
            endChapter: oldTasks[index].endChapter,
            endVerse: oldTasks[index].endVerse,
          ),
      ];
      await repository.updatePlan(
        existing.id,
        NewMemorizationPlan(
          title: existing.title,
          translationId: draft.translationId,
          bookId: existing.bookId,
          startChapter: existing.startChapter,
          endChapter: existing.endChapter,
          startDate: draft.startDate,
          endDate: draft.endDate,
          tasks: tasks,
          sourceKind: existing.sourceKind,
          sourceUrl: existing.sourceUrl,
          externalId: existing.externalId,
          revision: existing.revision,
          contentLocked: true,
        ),
      );
    });
  }

  Future<void> _saveCustomPlan(PlanEditorDraft draft, {int? planId}) async {
    await _runSave(() async {
      final scripture = await ref.read(scriptureRepositoryProvider.future);
      final repository = await ref.read(planRepositoryProvider.future);
      final completedTasks = planId == null
          ? const <PlanTask>[]
          : (await repository.listTasks(
              planId,
            )).where((task) => task.completed).toList(growable: false);
      final normalized = normalizeDraftForPendingWork(draft, completedTasks);
      final plan = await buildPlanFromDraft(
        scripture,
        normalized,
        completedTasks: completedTasks,
      );
      if (planId == null) {
        await repository.createPlan(plan);
      } else {
        await repository.updatePlan(planId, plan);
      }
    });
  }

  Future<void> _runSave(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
      final repository = await ref.read(planRepositoryProvider.future);
      await ref.read(dailyTaskReminderSchedulerProvider).reschedule(repository);
      if (!mounted) return;
      setState(() => _revision++);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('计划已保存到本机')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存计划失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _syncCloudPlans() async {
    setState(() => _working = true);
    try {
      final repository = await ref.read(planRepositoryProvider.future);
      final result = await syncPresetPlans(
        repository: repository,
        client: ref.read(cloudPlanFeedClientProvider),
      );
      if (!mounted) return;
      ref.read(presetPlanRevisionProvider.notifier).refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '同步完成：${result.manifest.plans.length} 个预置计划，'
            '新增 ${result.newPlanIds.length} 个',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('同步失败，请检查网络后重试')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _importCloudPlanFile() async {
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
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('JSON 文件不能超过 1 MB');
      }
      final repository = await ref.read(planRepositoryProvider.future);
      final source = utf8.decode(bytes);
      try {
        final plan = PlanExchange.decode(source);
        await repository.createPlan(plan);
        if (!mounted) return;
        setState(() => _revision++);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('计划已导入：完成状态已重置')));
        return;
      } on FormatException {
        // Existing published cloud-plan JSON remains supported below.
      }
      final manifest = CloudPlanManifest.parse(source);
      final result = await ref
          .read(cloudPlanImporterProvider)
          .importPushed(
            repository: repository,
            manifest: manifest,
            sourceUrl: 'local-file:///${Uri.encodeComponent(selected.name)}',
            today: _today(),
          );
      if (!mounted) return;
      setState(() => _revision++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '文件导入完成：新增 ${result.inserted}，更新 ${result.updated}，'
            '无需更新 ${result.unchanged}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('文件导入失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editCloudSource() async {
    final repository = await ref.read(planRepositoryProvider.future);
    final current = await repository.getSetting(
      'cloud_plan_source_url',
      defaultCloudPlanSourceUrl,
    );
    if (!mounted) return;
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('云端计划来源'),
        content: TextField(
          key: const Key('cloud-plan-source-url'),
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '公开 HTTPS JSON 地址',
            border: OutlineInputBorder(),
          ),
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
    if (result == null) return;
    final uri = Uri.tryParse(result);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入有效的 HTTPS JSON 地址')));
      }
      return;
    }
    await repository.setSetting('cloud_plan_source_url', uri.toString());
  }

  Future<_EditorData?> _loadEditorData({String? translationId}) async {
    final locale = Localizations.localeOf(context);
    try {
      final scripture = await ref.read(scriptureRepositoryProvider.future);
      final translations = await scripture.listTranslations();
      final preferredLanguage = locale.languageCode == 'zh' ? 'zh' : 'en';
      final translation = translationId == null
          ? translations.firstWhere(
              (item) => item.languageTag.startsWith(preferredLanguage),
              orElse: () => translations.first,
            )
          : translations.firstWhere(
              (item) => item.id == translationId,
              orElse: () => translations.first,
            );
      final catalog = ref.read(bookNameCatalogProvider);
      final rawBooks = await scripture.listBooks(
        translation.id,
        CanonId.protestant66,
      );
      final books = rawBooks
          .map(
            (book) => BibleBook(
              osisId: book.osisId,
              ordinal: book.ordinal,
              name: catalog.nameFor(book.osisId, locale),
              chapterCount: book.chapterCount,
            ),
          )
          .toList(growable: false);
      return _EditorData(translation, books, scripture);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开计划编辑器：$error')));
      }
      return null;
    }
  }

  Future<List<PlanPassageSelection>?> _pickPassages(_EditorData data) =>
      showDialog(
        context: context,
        builder: (_) => _PassagePickerDialog(
          books: data.books,
          scripture: data.scripture,
          translationId: data.translation.id,
        ),
      );

  String _translationLabel(String id) => switch (id) {
    'cmn-cu89t' => '繁體',
    'eng-web' => 'English',
    _ => '简体',
  };

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

final class _EditorData {
  const _EditorData(this.translation, this.books, this.scripture);
  final TranslationInfo translation;
  final List<BibleBook> books;
  final ScriptureRepository scripture;
}

class _PassagePickerDialog extends StatefulWidget {
  const _PassagePickerDialog({
    required this.books,
    required this.scripture,
    required this.translationId,
  });

  final List<BibleBook> books;
  final ScriptureRepository scripture;
  final String translationId;

  @override
  State<_PassagePickerDialog> createState() => _PassagePickerDialogState();
}

class _PassagePickerDialogState extends State<_PassagePickerDialog> {
  late BibleBook _startBook = widget.books.first;
  late BibleBook _endBook = widget.books.first;
  int _startChapter = 1;
  int _endChapter = 1;
  int? _startVerse;
  int? _endVerse;

  @override
  Widget build(BuildContext context) {
    final endBooks = widget.books
        .where((book) => book.ordinal >= _startBook.ordinal)
        .toList(growable: false);
    return AlertDialog(
      title: const Text('添加经文'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _bookField(
              '开始卷',
              _startBook,
              widget.books,
              (book) => setState(() {
                _startBook = book;
                _endBook = book;
                _startChapter = _endChapter = 1;
                _startVerse = _endVerse = null;
              }),
            ),
            _chapterField(
              '开始章',
              _startBook,
              _startChapter,
              (value) => setState(() {
                _startChapter = value;
                _startVerse = null;
                if (_endBook == _startBook && _endChapter < value)
                  _endChapter = value;
              }),
            ),
            _verseField(true),
            const Divider(),
            _bookField(
              '结束卷',
              _endBook,
              endBooks,
              (book) => setState(() {
                _endBook = book;
                _endChapter = book == _startBook ? _startChapter : 1;
                _endVerse = null;
              }),
            ),
            _chapterField(
              '结束章',
              _endBook,
              _endChapter,
              (value) => setState(() {
                _endChapter = value;
                _endVerse = null;
              }),
            ),
            _verseField(false),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('添加')),
      ],
    );
  }

  Widget _bookField(
    String label,
    BibleBook value,
    Iterable<BibleBook> books,
    ValueChanged<BibleBook> onChanged,
  ) => DropdownButtonFormField<String>(
    value: value.osisId,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final book in books)
        DropdownMenuItem(value: book.osisId, child: Text(book.name)),
    ],
    onChanged: (id) => onChanged(books.firstWhere((book) => book.osisId == id)),
  );

  Widget _chapterField(
    String label,
    BibleBook book,
    int value,
    ValueChanged<int> onChanged,
  ) => DropdownButtonFormField<int>(
    value: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (var chapter = 1; chapter <= book.chapterCount; chapter++)
        DropdownMenuItem(value: chapter, child: Text('$chapter')),
    ],
    onChanged: (chapter) {
      if (chapter != null) onChanged(chapter);
    },
  );

  Widget _verseField(bool start) {
    final book = start ? _startBook : _endBook;
    final chapter = start ? _startChapter : _endChapter;
    final selected = start ? _startVerse : _endVerse;
    return FutureBuilder<List<VerseUnit>>(
      future: widget.scripture.getChapter(
        widget.translationId,
        book.osisId,
        chapter,
      ),
      builder: (context, snapshot) {
        final verses = snapshot.data ?? const <VerseUnit>[];
        final usable = verses.map((unit) => unit.start.verse).toList();
        return DropdownButtonFormField<int>(
          value: usable.contains(selected) ? selected : null,
          decoration: InputDecoration(labelText: start ? '开始节' : '结束节'),
          items: [
            for (final verse in usable)
              DropdownMenuItem(value: verse, child: Text('$verse')),
          ],
          onChanged: (verse) => setState(() {
            if (start)
              _startVerse = verse;
            else
              _endVerse = verse;
          }),
        );
      },
    );
  }

  Future<void> _save() async {
    if (_startVerse == null || _endVerse == null) return;
    final start = (_startBook.ordinal, _startChapter, _startVerse!);
    final end = (_endBook.ordinal, _endChapter, _endVerse!);
    if (start.$1 > end.$1 ||
        (start.$1 == end.$1 &&
            (start.$2 > end.$2 || (start.$2 == end.$2 && start.$3 > end.$3))))
      return;
    final startIndex = widget.books.indexOf(_startBook);
    final endIndex = widget.books.indexOf(_endBook);
    final selections = <PlanPassageSelection>[];
    for (var index = startIndex; index <= endIndex; index++) {
      final book = widget.books[index];
      final startChapter = book == _startBook ? _startChapter : 1;
      final startVerse = book == _startBook ? _startVerse! : 1;
      final endChapter = book == _endBook ? _endChapter : book.chapterCount;
      final chapter = await widget.scripture.getChapter(
        widget.translationId,
        book.osisId,
        endChapter,
      );
      if (chapter.isEmpty) return;
      selections.add(
        PlanPassageSelection(
          bookId: book.osisId,
          startChapter: startChapter,
          startVerse: startVerse,
          endChapter: endChapter,
          endVerse: book == _endBook ? _endVerse! : chapter.last.end.verse,
        ),
      );
    }
    if (mounted) Navigator.pop(context, selections);
  }
}

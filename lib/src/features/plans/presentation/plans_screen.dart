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
import '../../reminder/reminder_providers.dart';
import '../application/plan_providers.dart';
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

enum _PlanAction { export, edit, restart }

class _PlansScreenState extends ConsumerState<PlansScreen> {
  static const _planJsonStoreChannel = MethodChannel(
    'app.biblerecite/plan_json_store',
  );
  int _revision = 0;
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
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
            data: (repository) => FutureBuilder<List<MemorizationPlan>>(
              key: ValueKey(_revision),
              future: repository.listPlans(),
              builder: (context, snapshot) {
                final plans = snapshot.data ?? const <MemorizationPlan>[];
                if (plans.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('我的计划', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    for (final plan in plans) _planCard(plan, localizations),
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
            data: (manifest) => Column(
              children: [
                for (final template in manifest.plans)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.auto_stories_outlined),
                        ),
                        title: Text(template.title),
                        subtitle: Text(
                          '${template.description} · ${template.passages.length} 天起',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _working
                            ? null
                            : () => _configureTemplate(template),
                      ),
                    ),
                  ),
              ],
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

  Widget _planCard(MemorizationPlan plan, AppLocalizations localizations) {
    final locked = plan.contentLocked;
    final completed =
        plan.totalTasks > 0 && plan.completedTasks == plan.totalTasks;
    return Card(
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
          ],
        ),
        subtitle: Text(
          locked
              ? '${plan.totalTasks} 段经文 · ${_translationLabel(plan.translationId)} · '
                    '${localizations.daysCount(plan.days)}'
              : '${plan.bookId} ${plan.startChapter}–${plan.endChapter}章 · '
                    '${plan.completedTasks}/${plan.totalTasks} · '
                    '${_translationLabel(plan.translationId)}',
        ),
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

  Future<void> _restartPlan(MemorizationPlan plan) async {
    await _runSave(() async {
      final repository = await ref.read(planRepositoryProvider.future);
      await repository.restartPlan(plan.id);
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
      SnackBar(content: Text('计划 JSON 已保存至 下载/BibleRecite/$name')),
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
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 20, right: 8),
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(
                    '${catalog.nameFor(task.bookId, locale)} ${task.startChapter}:${task.startVerse}'
                    '${task.endChapter == task.startChapter && task.endVerse == task.startVerse ? '' : '–${task.endChapter}:${task.endVerse}'}',
                  ),
                  trailing: Wrap(spacing: 2, children: [
                          TextButton(
                            key: Key('read-task-${task.id}'),
                            onPressed: () {
                              Navigator.of(context).pop();
                              context.push('/bible/${plan.translationId}/${task.bookId}/${task.startChapter}?verse=${task.startVerse}');
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
                          Navigator.of(context).pop();
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  RecitationPracticeScreen(request: request),
                            ),
                          );
                            },
                            child: const Text('背诵'),
                          ),
                        ]),
                  onTap: null,
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
        onAddPassage: () => _pickPassage(data),
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
        onAddPassage: () => _pickPassage(data),
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
        onAddPassage: plan.contentLocked ? null : () => _pickPassage(data),
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
      final source = await repository.getSetting(
        'cloud_plan_source_url',
        defaultCloudPlanSourceUrl,
      );
      final uri = Uri.parse(source);
      final manifest = await ref
          .read(cloudPlanFeedClientProvider)
          .fetchFirst(cloudPlanSourceCandidates(source));
      final result = await ref
          .read(cloudPlanImporterProvider)
          .importPushed(
            repository: repository,
            manifest: manifest,
            sourceUrl: uri.toString(),
            today: _today(),
          );
      if (!mounted) return;
      setState(() => _revision++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '同步完成：新增 ${result.inserted}，更新 ${result.updated}，'
            '无需更新 ${result.unchanged}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('同步失败：$error')));
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

  Future<PlanPassageSelection?> _pickPassage(_EditorData data) => showDialog(
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
    final endBooks = [_startBook];
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

  void _save() {
    if (_startVerse == null || _endVerse == null) return;
    final start = (_startBook.ordinal, _startChapter, _startVerse!);
    final end = (_endBook.ordinal, _endChapter, _endVerse!);
    if (start.$1 > end.$1 ||
        (start.$1 == end.$1 &&
            (start.$2 > end.$2 || (start.$2 == end.$2 && start.$3 > end.$3))))
      return;
    Navigator.pop(
      context,
      PlanPassageSelection(
        bookId: _startBook.osisId,
        startChapter: _startChapter,
        startVerse: _startVerse!,
        endChapter: _endChapter,
        endVerse: _endVerse!,
      ),
    );
  }
}
